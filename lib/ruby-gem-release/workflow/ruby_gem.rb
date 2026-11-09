# frozen_string_literal: true

require_relative '../tasks'
require_relative '../package/ruby_gem'
require_relative '../destination/ruby_gems'
require_relative '../source_control/git'
require_relative '../hosting/github_release'

module RubyGemRelease
  module Workflow
    class RubyGem
      attr_reader :version, :changelog, :package, :destination, :git, :hosting, :provider

      def initialize(version:, changelog:, provider: ExecutionProvider.current,
                     package: Package::RubyGem.new(gemspec: provider.fetch('GEMSPEC', provider.fetch('INPUT_GEMSPEC', '')) || '', directory: provider.directory),
                     destination: Destination::RubyGems.new,
                     git: SourceControl::Git.new(directory: provider.directory), hosting: Hosting::GitHubRelease.new,
                     validate: nil, success: nil, failure: nil)
        @version = version
        @changelog = changelog
        @package = package
        @destination = destination
        @git = git
        @hosting = hosting
        @provider = provider
        @validate = validate
        @success = success
        @failure = failure
      end

      def install_tasks
        Tasks.install(workflow: self, package: @package, destination: @destination, provider: @provider) do |tasks|
          install_callbacks(tasks)
        end
      end

      private

      def install_callbacks(tasks)
        tasks.validate { |ctx| validate_release(ctx) }
        tasks.prepare { |ctx| prepare_release(ctx.release) }
        tasks.publish { |ctx| publish(ctx.release) }
        tasks.bump { |ctx| prepare_next(ctx) }
        tasks.success(&@success) if @success
        tasks.failure(&@failure) if @failure
      end

      def validate_release(ctx)
        return @validate.call(ctx) if @validate

        @changelog ? @changelog.pending? : true
      end

      def prepare_release(release)
        @git.stage_changes! do
          select_version!(release.version) unless @provider.fetch('INPUT_VERSION', '').empty?
          @changelog&.release!(release.with_version(@version.read))
        end
      end

      def select_version!(version)
        raise ArgumentError, 'version object must implement set! when selecting a release version' unless @version.respond_to?(:set!)

        @version.set!(version)
      end

      def publish(release)
        @destination.check_version!(name: @package.name, version: release.version)
        @git.commit!(release)
        @package.build!(release)
        @git.tag!(release)
        @destination.publish!(release, package: @package)
        @git.push!(release)
        @hosting&.publish!(release, package: @package)
      end

      def prepare_next(ctx)
        next_release = nil
        @git.stage_changes! do
          next_release = ctx.release.with_next_version(@version.increment!)
          @changelog&.prepare_next!(next_release)
        end
        @git.commit_next!(next_release)
        @git.push!
        ctx.record_next_version!(next_release.next_version)
      end
    end
  end
end
