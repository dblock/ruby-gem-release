# frozen_string_literal: true

require_relative 'ruby_gem'
require_relative '../semantic_release'
require_relative '../changelog/generated'

module RubyGemRelease
  module Workflow
    class SemanticRubyGem < RubyGem
      attr_reader :semantic_release

      def initialize(semantic_release: SemanticRelease.new, changelog: Changelog::Generated.new, bump: false, **)
        raise ArgumentError, 'bump must be true or false' unless [true, false].include?(bump)

        @semantic_release = semantic_release
        @bump = bump
        super(changelog: changelog, **)
      end

      private

      def install_callbacks(tasks)
        tasks.validate { |ctx| validate_with_hooks(ctx) }
        tasks.prepare { |ctx| prepare_release(ctx) }
        install_result_callbacks(tasks)
        tasks.failure(&@failure) if @failure
      end

      def install_result_callbacks(tasks)
        tasks.publish { |ctx| with_decision(ctx) { publish(ctx) } }
        tasks.bump { |ctx| with_decision(ctx) { prepare_next(ctx) if @bump } }
        tasks.success { |ctx| with_decision(ctx) { @success&.call(ctx) } }
      end

      def with_decision(ctx)
        checked_decision(ctx)
        yield
      end

      def validate_release(ctx)
        decision = ctx.analysis || @semantic_release.analyze(head: @provider.fetch('SOURCE_COMMIT'), explicit_version: @provider.fetch('INPUT_VERSION', ''))
        ctx.record_analysis!(decision) unless ctx.analysis
        raise ArgumentError, 'Nothing to release: no release-eligible commits' unless decision.release?

        @validate&.call(ctx)
      end

      def checked_decision(ctx)
        raise ArgumentError, 'semantic release requires a persisted release decision' unless ctx.analysis&.release?

        ctx.analysis.check!(head: @provider.fetch('SOURCE_COMMIT'), explicit_version: @provider.fetch('INPUT_VERSION', ''), version: ctx.release.version)
        ctx.analysis
      end

      def prepare_release(ctx)
        checked_decision(ctx)
        super
      end

      def prepare_release_files(release)
        select_version!(release.version)
        @changelog&.release!(release)
      end
    end
  end
end
