# frozen_string_literal: true

module RubyGemRelease
  class ReleaseFailure
    class CapturedError < StandardError
      attr_reader :original_class, :stage, :hook, :hook_index

      def self.capture(error, **details)
        new(original_class: error.class.name || error.class.to_s, message: error.message, backtrace: error.backtrace, **details)
      end

      def self.from_h(attributes)
        new(original_class: attributes.fetch('class'), message: attributes.fetch('message'), backtrace: attributes.fetch('backtrace'),
            stage: attributes['stage'], hook: attributes['hook'], hook_index: attributes['hook_index'])
      end

      def initialize(original_class:, message:, backtrace:, stage: nil, hook: nil, hook_index: nil)
        @original_class = original_class.freeze
        @stage = stage&.to_sym
        @hook = hook&.to_sym
        @hook_index = hook_index
        super(message)
        set_backtrace(backtrace)
      end

      def to_h
        { 'class' => original_class, 'message' => message, 'backtrace' => backtrace }.merge(
          { 'stage' => stage&.to_s, 'hook' => hook&.to_s, 'hook_index' => hook_index }.compact
        )
      end
    end

    attr_reader :phase, :error, :context

    def initialize(phase:, error:, context:)
      @phase = phase.dup.freeze
      @error = error
      @context = context
      freeze
    end
  end
end
