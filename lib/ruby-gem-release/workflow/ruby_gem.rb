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
                     package: Package::RubyGem.new(gemspec: provider.fetch('GEMSPEC_PATH', provider.fetch('INPUT_GEMSPEC_PATH', '')) || '', directory: provider.directory),
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

      def checkpoint!(context)
        prepare_publication(context.release)
      end

      def published?(release)
        @package.respond_to?(:built?) && @package.built?(release) && @destination.published?(release, package: @package)
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

        return if @changelog.nil? || @changelog.released?(ctx.release.version) || @changelog.pending?

        raise ArgumentError, 'Nothing to release: no pending changelog notes'
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

      def prepare_publication(release)
        @git.commit!(release)
        @package.build!(release)
        @git.tag!(release)
      end

      def publish(release)
        prepare_publication(release)
        @destination.publish!(release, package: @package)
        @git.push!(release)
        @hosting&.publish!(release, package: @package)
      end

      def prepare_next(ctx)
        next_release = stage_next!(ctx.release)
        @git.commit_next!(next_release)
        @git.push!
        ctx.record_next_version!(next_release.next_version)
      end

      def stage_next!(release)
        next_release = nil
        @git.stage_changes! do
          next_release = release.with_next_version(@version.increment!(from: release.version))
          @changelog&.prepare_next!(next_release)
        end
        next_release
      end
    end
  end
end
