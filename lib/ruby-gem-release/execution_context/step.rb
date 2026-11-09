# frozen_string_literal: true

module RubyGemRelease
  class ExecutionContext
    class Step
      attr_reader :id

      def initialize(id:)
        raise ArgumentError, 'step ID must be a nonempty string' unless id.is_a?(String) && !id.empty?

        @id = id.dup.freeze
        freeze
      end
    end
  end
end
