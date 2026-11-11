# frozen_string_literal: true

require_relative '../tasks'
require_relative '../package/ruby_gem'
require_relative '../destination/ruby_gems'
require_relative '../source_control/git'
require_relative '../hosting/github_release'
require_relative 'hooks'

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

      def before(stage, &)
        hooks.register(:before, stage, &)
        self
      end

      def after(stage, &)
        hooks.register(:after, stage, &)
        self
      end

      def run_stage(stage, context, **, &)
        hooks.run(stage, context, **, &)
      end

      def failure_details(error)
        hooks.failure_details(error)
      end

      def hooks?(stage)
        hooks.registered?(stage)
      end

      def install_tasks
        Tasks.install(workflow: self, package: @package, destination: @destination, provider: @provider) do |tasks|
          install_callbacks(tasks)
        end
      end

      def checkpoint!(context)
        run_stage(:checkpoint, context) { prepare_publication(context) }
      end

      def published?(release)
        @package.respond_to?(:built?) && @package.built?(release) && @destination.published?(release, package: @package)
      end

      private

      def hooks
        @hooks ||= Hooks.new
      end

      def install_callbacks(tasks)
        tasks.validate { |ctx| validate_with_hooks(ctx) }
        tasks.prepare { |ctx| prepare_release(ctx) }
        tasks.publish { |ctx| publish(ctx) }
        tasks.bump { |ctx| prepare_next(ctx) }
        tasks.success(&@success) if @success
        tasks.failure(&@failure) if @failure
      end

      def validate_with_hooks(ctx)
        run_stage(:validate, ctx, after_context: -> { ctx.refresh }) do
          raise ArgumentError, 'Release validation failed: callback returned false' if validate_release(ctx) == false
        end
      end

      def validate_release(ctx)
        return @validate.call(ctx) if @validate

        return if @changelog.nil? || @changelog.released?(ctx.release.version) || @changelog.pending?

        raise ArgumentError, 'Nothing to release: no pending changelog notes'
      end

      def prepare_release(ctx)
        @git.stage_changes! do
          run_stage(:prepare_release, ctx) { prepare_release_files(ctx.release) }
        end
      end

      def prepare_release_files(release)
        select_version!(release.version) unless @provider.fetch('INPUT_VERSION', '').empty?
        @changelog&.release!(release.with_version(@version.read))
      end

      def select_version!(version)
        raise ArgumentError, 'version object must implement set! when selecting a release version' unless @version.respond_to?(:set!)

        @version.set!(version)
      end

      def prepare_publication(ctx)
        run_stage(:commit_release, ctx) { @git.commit!(ctx.release) }
        run_stage(:build_package, ctx) { @package.build!(ctx.release) }
        run_stage(:tag_release, ctx) { @git.tag!(ctx.release) }
      end

      def publish(ctx)
        prepare_publication(ctx)
        run_stage(:publish_registry, ctx) { @destination.publish!(ctx.release, package: @package) }
        run_stage(:push_release, ctx) { @git.push!(ctx.release) }
        run_stage(:publish_hosted_release, ctx) { @hosting.publish!(ctx.release, package: @package) } if @hosting
      end

      def prepare_next(ctx)
        next_ctx = stage_next!(ctx)
        run_stage(:commit_next, next_ctx) { @git.commit_next!(next_ctx.release) }
        run_stage(:push_next, next_ctx) { @git.push! }
        ctx.record_next_version!(next_ctx.release.next_version)
      end

      def stage_next!(ctx)
        next_ctx = ctx
        @git.stage_changes! do
          run_stage(:prepare_next, ctx, after_context: -> { next_ctx }) do
            next_ctx = ctx.with(release: ctx.release.with_next_version(@version.increment!(from: ctx.release.version)))
            @changelog&.prepare_next!(next_ctx.release)
          end
        end
        next_ctx
      end
    end
  end
end
