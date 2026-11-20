# frozen_string_literal: true

require_relative 'lifecycle'
require_relative '../package/ruby_gem'
require_relative '../destination/ruby_gems'
require_relative '../source_control/git'
require_relative '../hosting/github_release'
require_relative '../version/interface'

module RubyGemRelease
  module Workflow
    class RubyGem
      include Lifecycle

      NEXT_VERSIONS = %i[major minor patch].freeze

      attr_reader :version, :changelog, :package, :destination, :git, :hosting, :provider

      def initialize(version:, changelog:, provider: ExecutionProvider.current,
                     package: Package::RubyGem.new(gemspec: provider.fetch('GEMSPEC_PATH', provider.fetch('INPUT_GEMSPEC_PATH', '')) || '', directory: provider.directory),
                     destination: Destination::RubyGems.new,
                     git: SourceControl::Git.new(directory: provider.directory), hosting: Hosting::GitHubRelease.new,
                     validate: nil, success: nil, failure: nil, next_version: :patch)
        configure_version!(version, next_version)
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

      def environment
        Environment.new(provider: @provider)
      end

      private

      def configure_version!(version, next_version)
        @version = Version::Interface.check!(version)
        part = next_version.to_sym if next_version.is_a?(String) || next_version.is_a?(Symbol)
        raise ArgumentError, 'next_version must be :major, :minor, or :patch' unless NEXT_VERSIONS.include?(part)
        raise ArgumentError, "version object's increment! must accept part: to use next_version: #{part.inspect}" unless part == :patch || increment_accepts_part?

        @next_version = part
      end

      def increment_accepts_part?
        @version.method(:increment!).parameters.any? { |type, name| %i[keyrest rest].include?(type) || (%i[key keyreq].include?(type) && name == :part) }
      end

      def increment_options
        @next_version == :patch ? {} : { part: @next_version }
      end

      def install_callbacks(tasks)
        tasks.validate { |ctx| validate_with_hooks(ctx) }
        tasks.prepare { |ctx| prepare_release(ctx) }
        tasks.publish { |ctx| publish(ctx) }
        tasks.bump { |ctx| prepare_next(ctx) }
        tasks.success(&@success) if @success
        tasks.failure(&@failure) if @failure
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
        @version.set!(release.version) unless @provider.fetch('INPUT_VERSION', '').empty?
        @changelog&.release!(release.with_version(@version.read))
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
            next_ctx = ctx.with(release: ctx.release.with_next_version(@version.increment!(from: ctx.release.version, **increment_options)))
            @changelog&.prepare_next!(next_ctx.release)
          end
        end
        next_ctx
      end
    end
  end
end
