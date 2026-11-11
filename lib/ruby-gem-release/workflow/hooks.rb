# frozen_string_literal: true

module RubyGemRelease
  module Workflow
    class Hooks
      STAGES = %i[capture resolve_version validate prepare_release authenticate checkpoint commit_release build_package tag_release
                  publish_registry push_release publish_hosted_release prepare_next commit_next push_next success failure].freeze

      def initialize
        @hooks = { before: {}, after: {} }
      end

      def register(timing, stage, &block)
        raise ArgumentError, "unknown lifecycle stage: #{stage.inspect}" unless STAGES.include?(stage)
        raise ArgumentError, 'hook requires a block' unless block

        (@hooks.fetch(timing)[stage] ||= []) << block
      end

      def registered?(stage)
        @hooks.values.any? { |stages| !stages.fetch(stage, []).empty? }
      end

      def run(stage, context, after_context: nil)
        call_hooks(:before, stage, context)
        result = yield
        call_hooks(:after, stage, after_context ? after_context.call : context) unless @hooks.fetch(:after).fetch(stage, []).empty?
        result
      rescue StandardError => e
        record_failure(e, stage: stage)
        raise
      end

      def failure_details(error)
        @failure_error.equal?(error) ? @failure_details : {}
      end

      private

      def call_hooks(timing, stage, context)
        @hooks.fetch(timing).fetch(stage, []).each_with_index do |block, index|
          block.call(context.with(stage: stage, hook: timing, hook_index: index + 1))
        rescue StandardError => e
          record_failure(e, stage: stage, hook: timing, hook_index: index + 1)
          raise
        end
      end

      def record_failure(error, **details)
        return if @failure_error.equal?(error)

        @failure_error = error
        @failure_details = details
      end
    end
  end
end
