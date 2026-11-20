# frozen_string_literal: true

require 'date'
require 'fileutils'
require 'json'
require 'open3'
require 'rubygems/name_tuple'
require_relative '../release'
require_relative '../execution_provider'
require_relative '../package/prebuilt'
require_relative '../destination/ruby_gems'
require_relative '../hosting/github_release'

module RubyGemRelease
  module Workflow
    # Publishes a release sealed by an unprivileged build job. Loads only the
    # standard library and this gem, never the project's bundle or Rakefile, so
    # project code does not run while publication credentials are available.
    class IsolatedPublication
      FORMAT = 1
      FILE = 'publication.json'
      PUBLICATION_STAGES = %i[authenticate publish_registry push_release publish_hosted_release push_next success failure].freeze
      SHA = /\A[0-9a-f]{40}\z/

      # Build job: rejects components and hooks the publish job cannot reproduce.
      def self.check!(workflow, callbacks:)
        check_components!(workflow)
        raise ArgumentError, 'isolated publication runs no project success or failure callbacks' if callbacks

        stages = PUBLICATION_STAGES.select { |stage| workflow.hooks?(stage) }
        raise ArgumentError, "isolated publication runs no project hooks for #{stages.join(', ')}" unless stages.empty?
      end

      def self.check_components!(workflow)
        { package: Package::RubyGem, destination: Destination::RubyGems, git: SourceControl::Git }.each do |name, klass|
          object = workflow.public_send(name)
          raise ArgumentError, "isolated publication requires the default #{name}" unless object.instance_of?(klass) || local_adapter?(object)
        end
        repository = workflow.provider.fetch('GITHUB_REPOSITORY', nil)
        raise ArgumentError, 'isolated publication requires the default GitHub Release hosting or hosting: nil' unless reproducible_hosting?(workflow.hosting, repository)
      end

      # The publish job creates releases in the calling repository, which the
      # default hosting also selects from GITHUB_REPOSITORY.
      def self.reproducible_hosting?(hosting, repository)
        hosting.nil? || local_adapter?(hosting) || (hosting.instance_of?(Hosting::GitHubRelease) && [nil, repository].include?(hosting.repository))
      end

      # The RSpec helpers' local adapters stand in for RubyGems and GitHub
      # Releases, and the helper's publish process supplies them again.
      def self.local_adapter?(object)
        defined?(RubyGemRelease::RSpec::Destination) && [RubyGemRelease::RSpec::Destination, RubyGemRelease::RSpec::Hosting].any? { |klass| object.instance_of?(klass) }
      end

      # Build job: preserves the release and next development commits and the
      # values the publish job needs, alongside the gem built at the checkpoint.
      def self.seal!(workflow:, release:, provider:)
        workflow.git.write_bundle(release)
        path = File.join(provider.directory, FILE)
        File.write(path, JSON.generate(handoff(workflow, release, provider)))
        path
      end

      def self.handoff(workflow, release, provider)
        git = workflow.git
        { 'format' => FORMAT, 'version' => release.version, 'gemspec_version' => release.gemspec_version, 'date' => release.date.iso8601,
          'notes' => release.notes, 'next_version' => release.next_version, 'branch' => provider.fetch('DEFAULT_BRANCH'),
          'source_commit' => provider.fetch('SOURCE_COMMIT'), 'release_commit' => git.tag_commit(release.version),
          'next_commit' => release.next_version && git.head, 'hosting' => hosting_options(workflow.hosting) }
      end

      def self.hosting_options(hosting)
        hosting && { 'latest' => hosting.respond_to?(:latest) ? hosting.latest : nil }
      end

      def initialize(provider: ExecutionProvider.current, destination: Destination::RubyGems.new, hosting: nil, remote: 'origin')
        @provider = provider
        @destination = destination
        @hosting = hosting
        @remote = remote
      end

      # Publish job: pushes the release commit before the gem, so a branch that
      # rejects the release token fails before anything is published.
      def publish!
        load_handoff!
        verify_source!
        push_release_commit!
        publish_package!
        push_tag!
        hosting&.publish!(@release, package: @package)
        push_next_commit!
        @release
      end

      private

      def load_handoff!
        @data = JSON.parse(File.read(File.join(directory, FILE)))
        raise ArgumentError, 'unsupported isolated publication format' unless @data.is_a?(Hash) && @data['format'] == FORMAT

        @branch = @data.fetch('branch')
        @release = Release.new(version: @data.fetch('version'), gemspec_version: @data.fetch('gemspec_version'), date: Date.iso8601(@data.fetch('date')),
                               next_version: @data['next_version'], notes: @data['notes'])
        @package = prebuilt_package
      end

      def prebuilt_package
        manifest = JSON.parse(File.read(File.join(directory, 'release.json')))
        name, version = manifest.values_at('name', 'version')
        platform = manifest.fetch('platform', 'ruby')
        raise 'Package manifest does not match the sealed release' unless version == @release.version

        Package::Prebuilt.new(path: named_archive(name, version, platform), sha256: manifest.fetch('sha256'), name: name, version: version, platform: platform)
                         .tap { |package| package.artifact(@release) }
      end

      # Prebuilt packages and hosted assets use the gem's own filename.
      def named_archive(name, version, platform)
        path = File.join(directory, "#{Gem::NameTuple.new(name, Gem::Version.new(version), platform).full_name}.gem")
        FileUtils.cp(File.join(directory, 'release.gem'), path)
        path
      end

      def verify_source!
        verify_dispatch!
        import_bundle!
        raise 'Release bundle does not contain the sealed commits' unless git('rev-parse', 'refs/ruby-gem-release/sealed') == (next_commit || release_commit)
        raise 'Sealed release tag does not point at the release commit' unless git('cat-file', '-t', tag_ref) == 'commit' && git('rev-parse', tag_ref) == release_commit

        verify_parents!
      end

      def verify_parents!
        raise 'Sealed release commit must have the dispatched commit as its only parent' unless parents(release_commit) == [source_commit]
        raise 'Sealed development commit must have the release commit as its only parent' if next_commit && parents(next_commit) != [release_commit]
      end

      def verify_dispatch!
        commits = @data.values_at('source_commit', 'release_commit', 'next_commit').compact
        raise ArgumentError, 'sealed commits must be full SHA-1 object names' unless commits.all? { |commit| SHA.match?(commit) }
        raise 'Releases must run from the default branch' unless @branch == @provider.fetch('DEFAULT_BRANCH') && @provider.ref == "refs/heads/#{@branch}"
        raise 'Sealed release was not built from the dispatched commit' unless source_commit == @provider.fetch('GITHUB_SHA')
      end

      def import_bundle!
        bundle = File.join(directory, 'release.bundle')
        git('bundle', 'verify', bundle)
        git('fetch', '--no-tags', bundle, "+#{tag_ref}:#{tag_ref}", '+HEAD:refs/ruby-gem-release/sealed')
      end

      def push_release_commit!
        head = remote_head
        return if [release_commit, next_commit].include?(head) || ancestor?(release_commit, head)
        raise 'Default branch advanced; start a new release' unless head == source_commit

        git('push', @remote, "#{release_commit}:refs/heads/#{@branch}")
      end

      def publish_package!
        return if @destination.published?(@release, package: @package)

        @destination.authenticate!(provider: @provider)
        @destination.publish!(@release, package: @package)
      end

      def push_tag!
        existing = git('ls-remote', '--tags', @remote, tag_ref, "#{tag_ref}^{}").lines.map(&:split).to_h { |sha, ref| [ref, sha] }
        remote = existing["#{tag_ref}^{}"] || existing[tag_ref]
        raise 'Remote release tag points at another commit' if remote && remote != release_commit

        git('push', @remote, tag_ref) unless remote
      end

      def push_next_commit!
        return unless next_commit

        head = remote_head
        return if ancestor?(next_commit, head)
        raise 'Default branch advanced; start a new release' unless head == release_commit

        git('push', @remote, "#{next_commit}:refs/heads/#{@branch}")
      end

      def hosting
        return unless @data['hosting']

        @hosting || Hosting::GitHubRelease.new(latest: @data['hosting']['latest'])
      end

      def remote_head
        git('fetch', '--no-tags', @remote, "+refs/heads/#{@branch}:refs/remotes/#{@remote}/#{@branch}")
        git('rev-parse', "refs/remotes/#{@remote}/#{@branch}")
      end

      def parents(commit)
        git('rev-list', '--parents', '-n', '1', commit).split.drop(1)
      end

      def ancestor?(commit, descendant)
        _output, error, status = Open3.capture3('git', 'merge-base', '--is-ancestor', commit, descendant)
        raise "Cannot inspect Git ancestry: #{error}" unless [0, 1].include?(status.exitstatus)

        status.success?
      end

      def source_commit = @data.fetch('source_commit')
      def release_commit = @data.fetch('release_commit')
      def next_commit = @data['next_commit']
      def tag_ref = "refs/tags/v#{@release.version}"

      def directory
        @provider.directory or raise ArgumentError, 'isolated publication requires a release data directory'
      end

      def git(*)
        output, error, status = Open3.capture3('git', *)
        raise "Git command failed: #{error.strip}\n#{output.strip}" unless status.success?

        output.strip
      end
    end
  end
end
