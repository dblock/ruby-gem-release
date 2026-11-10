# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'
require_relative 'git/preparation'

module RubyGemRelease
  module SourceControl
    class Git
      def initialize(branch: nil, remote: 'origin', directory: nil)
        @remote = remote
        @branch = branch || ENV.fetch('DEFAULT_BRANCH', nil)
        directory ||= ENV.fetch('RELEASE_DATA_DIR', nil)
        @directory = directory.to_s.empty? ? Dir.mktmpdir('ruby-gem-release-git-') : directory
      end

      def configure!(name: 'ruby-gem-release', email: 'ruby-gem-release@localhost')
        [name, email].each do |value|
          raise ArgumentError, 'Git identity must be nonempty and contain no line breaks' unless value.is_a?(String) && !value.strip.empty? && !value.match?(/[\r\n]/)
        end
        run('config', '--local', 'user.name', name)
        run('config', '--local', 'user.email', email)
      end

      def head
        run('rev-parse', 'HEAD').strip
      end

      def timestamp(commit)
        run('show', '-s', '--format=%ct', commit).strip
      end

      def check_current!(_release, expected: head, allow_ancestor: false)
        run('fetch', @remote, branch, '--tags')
        raise 'Default branch advanced; start a new release' unless remote_head == expected || (allow_ancestor && ancestor?(expected, remote_head))
      end

      def check_clean!
        preparation.check_clean!
      end

      def stage_changes!(&)
        preparation.stage_changes!(&)
      end

      def commit!(release)
        @release = release
        @next_commit_parent = nil
        @source_commit = ENV['SOURCE_COMMIT'] || head
        existing = tag_commit(release.version)
        return reuse_release!(existing) if existing

        commit_changes("Prepare release #{release.version}", required: false)
      end

      def commit_next!(release)
        raise ArgumentError, 'next development iteration version is required' if release.next_version.to_s.empty?

        @release = release
        @next_commit_parent = head
        existing = next_iteration(release)
        return reuse_iteration!(existing, release) if existing

        commit_changes("Prepare next development iteration, #{release.next_version}", required: true)
      end

      def tag!(release)
        @release = release
        ensure_clean!
        fetch!
        existing = tag_commit(release.version)
        raise "Release tag already exists at another commit: v#{release.version}" if existing && existing != head

        raise 'Default branch advanced; start a new release' unless release_current?(existing)

        run('tag', "v#{release.version}") unless existing
        write_bundle(release)
      end

      def push!(release = @release)
        raise ArgumentError, 'a release context is required before pushing' unless release

        fetch!
        @next_commit_parent ? push_iteration!(release) : push_release!(release)
      end

      def fetch!
        run('fetch', @remote, branch, '--tags')
      end

      def tag_commit(version)
        ref = "refs/tags/v#{version}"
        _output, error, status = Open3.capture3('git', 'show-ref', '--verify', '--quiet', ref)
        return if status.exitstatus == 1
        raise "Cannot inspect release tag: #{error}" unless status.success?

        run('rev-parse', "#{ref}^{commit}").strip
      end

      def next_iteration(release)
        fetch!
        released = tag_commit(release.version)
        return unless released && ancestor?(released, remote_head)

        candidate = iteration_after(released)
        return unless candidate

        version = run('log', '-1', '--format=%s', candidate)[/\APrepare next development iteration, (\d+\.\d+\.\d+)\n?\z/, 1]
        { commit: candidate, version: version, tree: run('rev-parse', "#{candidate}^{tree}").strip } if version
      end

      private

      def reuse_release!(existing)
        preparation.verify!
        raise 'Existing release tag differs from the intended tree' unless run('write-tree').strip == run('rev-parse', "#{existing}^{tree}").strip

        run('update-ref', 'HEAD', existing, head)
        preparation.clear!
        head
      end

      def reuse_iteration!(existing, release)
        preparation.verify!
        raise 'Existing development iteration differs from the intended changes' unless existing.fetch(:version) == release.next_version && existing.fetch(:tree) == run('write-tree').strip

        run('update-ref', 'HEAD', existing.fetch(:commit), head)
        preparation.clear!
        head
      end

      def release_current?(existing)
        expected = @source_commit || ENV.fetch('SOURCE_COMMIT')
        remote_head == expected || (existing && ancestor?(head, remote_head))
      end

      def write_bundle(release)
        FileUtils.mkdir_p(@directory)
        run('bundle', 'create', File.join(@directory, 'release.bundle'), 'HEAD', "refs/tags/v#{release.version}")
      end

      def push_iteration!(release)
        return if ancestor?(head, remote_head)

        check_current!(release, expected: @next_commit_parent)
        run('push', @remote, "HEAD:refs/heads/#{branch}")
      end

      def push_release!(release)
        return push_missing_tag(release) if ancestor?(head, remote_head)

        check_current!(release, expected: @source_commit || ENV.fetch('SOURCE_COMMIT'))
        run('push', '--atomic', @remote, "HEAD:refs/heads/#{branch}", "refs/tags/v#{release.version}")
      end

      def iteration_after(released)
        candidate = run('rev-list', '--first-parent', '--reverse', "#{released}..#{remote_head}").lines.first&.strip
        candidate if candidate && run('rev-list', '--parents', '-n', '1', candidate).split == [candidate, released]
      end

      def ancestor?(commit, descendant)
        _output, error, status = Open3.capture3('git', 'merge-base', '--is-ancestor', commit, descendant)
        raise "Cannot inspect Git ancestry: #{error}" unless [0, 1].include?(status.exitstatus)

        status.success?
      end

      def remote_tag(version)
        output = run('ls-remote', '--tags', @remote, "refs/tags/v#{version}", "refs/tags/v#{version}^{}")
        entries = output.lines.map(&:split).to_h { |sha, ref| [ref, sha] }
        entries["refs/tags/v#{version}^{}"] || entries["refs/tags/v#{version}"]
      end

      def push_missing_tag(release)
        existing = remote_tag(release.version)
        raise 'Remote release tag points at another commit' if existing && existing != head

        run('push', @remote, "refs/tags/v#{release.version}") unless existing
      end

      def branch
        @branch ||= run('symbolic-ref', "refs/remotes/#{@remote}/HEAD").strip.delete_prefix("refs/remotes/#{@remote}/")
      end

      def remote_head
        run('rev-parse', "refs/remotes/#{@remote}/#{branch}").strip
      end

      def ensure_clean!
        raise 'Gem build changed the working tree after the release commit' unless run('status', '--porcelain', '--untracked-files=all').empty?
      end

      def commit_changes(message, required:)
        preparation.verify!
        output = run('diff', '--cached', '--name-only', '-z')
        raise 'Preparing the next development iteration did not change any files' if required && output.empty?

        if output.empty?
          preparation.clear!
          return head
        end

        run('commit', '-m', message)
        preparation.clear!
        head
      end

      def preparation
        @preparation ||= Preparation.new(directory: @directory, &method(:run))
      end

      def run(*)
        output, error, status = Open3.capture3('git', *)
        raise "Git command failed: #{error.strip}\n#{output.strip}" unless status.success?

        output
      end
    end
  end
end
