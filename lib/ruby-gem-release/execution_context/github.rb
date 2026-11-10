# frozen_string_literal: true

require 'json'
require_relative '../execution_context'
require_relative 'github/step'
require_relative 'github/run'

module RubyGemRelease
  class ExecutionContext
    class GitHub < ExecutionContext
      def self.step_id(task, environment: ENV)
        environment.fetch('RELEASE_STEP_ID', task)
      end

      def self.steps(environment: ENV)
        attributes = JSON.parse(environment.fetch('RELEASE_STEPS_JSON', '{}'))
        raise ArgumentError, 'release steps must be an object' unless attributes.is_a?(Hash)

        attributes.to_h do |id, values|
          raise ArgumentError, 'release step must be an object' unless values.is_a?(Hash)

          [id.freeze, Step.new(id: id, outcome: values['outcome'], conclusion: values['conclusion'])]
        end.freeze
      end

      def initialize(release:, task:, state:, workflow: nil, environment: ENV, analysis: state&.analysis)
        super(release: release, task: task, state: state, workflow: workflow, analysis: analysis,
              step: Step.new(id: self.class.step_id(task, environment: environment)),
              steps: self.class.steps(environment: environment), run: Run.new(environment: environment))
      end
    end
  end
end
