# frozen_string_literal: true

require_relative '../tasks'
require_relative 'hooks'

module RubyGemRelease
  module Workflow
    # Shared hook registration, task installation, and publication checks.
    # Including workflows set @package, @destination, and @provider, and
    # define install_callbacks, validate_release, and prepare_publication.
    module Lifecycle
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

      def validate_with_hooks(ctx)
        run_stage(:validate, ctx, after_context: -> { ctx.refresh }) do
          raise ArgumentError, 'Release validation failed: callback returned false' if validate_release(ctx) == false
        end
      end
    end
  end
end
