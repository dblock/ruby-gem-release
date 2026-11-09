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

      def initialize(release:, task:, state:, workflow: nil, environment: ENV)
        super(release: release, task: task, state: state, workflow: workflow,
              step: Step.new(id: self.class.step_id(task, environment: environment)),
              steps: parse_steps(environment.fetch('RELEASE_STEPS', '{}')), run: Run.new(environment: environment))
      end

      private

      def parse_steps(json)
        attributes = JSON.parse(json)
        raise ArgumentError, 'release steps must be an object' unless attributes.is_a?(Hash)

        attributes.to_h { |id, values| [id.freeze, Step.new(id: id, **step_attributes(values))] }.freeze
      end

      def step_attributes(values)
        raise ArgumentError, 'release step must be an object' unless values.is_a?(Hash)

        { outcome: values['outcome'], conclusion: values['conclusion'], outputs: values.fetch('outputs', {}) }
      end
    end
  end
end
