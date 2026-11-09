# frozen_string_literal: true

module RubyGemRelease
  class ReleaseFailure
    class CapturedError < StandardError
      attr_reader :original_class

      def self.capture(error)
        new(original_class: error.class.name || error.class.to_s, message: error.message, backtrace: error.backtrace)
      end

      def self.from_h(attributes)
        new(original_class: attributes.fetch('class'), message: attributes.fetch('message'), backtrace: attributes.fetch('backtrace'))
      end

      def initialize(original_class:, message:, backtrace:)
        @original_class = original_class.freeze
        super(message)
        set_backtrace(backtrace)
      end

      def to_h
        { 'class' => original_class, 'message' => message, 'backtrace' => backtrace }
      end
    end

    attr_reader :phase, :error, :release

    def initialize(phase:, error:, release: nil)
      @phase = phase.dup.freeze
      @error = error
      @release = release
      freeze
    end
  end
end
