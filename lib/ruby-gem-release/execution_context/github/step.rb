# frozen_string_literal: true

require_relative '../../execution_context'

module RubyGemRelease
  class ExecutionContext
    class GitHub < ExecutionContext
      class Step < ExecutionContext::Step
        attr_reader :outcome, :conclusion

        def initialize(id:, outcome: nil, conclusion: nil)
          @outcome = status(outcome)
          @conclusion = status(conclusion)
          super(id: id)
        end

        private

        def status(value)
          return if value.nil?
          raise ArgumentError, "invalid step status: #{value.inspect}" unless %w[success failure cancelled skipped].include?(value)

          value.dup.freeze
        end
      end
    end
  end
end
