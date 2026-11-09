# frozen_string_literal: true

require_relative '../../execution_context'

module RubyGemRelease
  class ExecutionContext
    class GitHub < ExecutionContext
      class Step < ExecutionContext::Step
        attr_reader :outcome, :conclusion, :outputs

        def initialize(id:, outcome: nil, conclusion: nil, outputs: {})
          @outcome = status(outcome)
          @conclusion = status(conclusion)
          @outputs = public_outputs(outputs)
          super(id: id)
        end

        private

        def public_outputs(outputs)
          raise ArgumentError, 'step outputs must be an object' unless outputs.is_a?(Hash)

          outputs.slice('proceed').to_h do |name, value|
            raise ArgumentError, 'step output must be a string' unless value.is_a?(String)

            [name.freeze, value.dup.freeze]
          end.freeze
        end

        def status(value)
          return if value.nil?
          raise ArgumentError, "invalid step status: #{value.inspect}" unless %w[success failure cancelled skipped].include?(value)

          value.dup.freeze
        end
      end
    end
  end
end
