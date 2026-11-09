# frozen_string_literal: true

require_relative 'execution_context/step'

module RubyGemRelease
  class ExecutionContext
    attr_reader :release, :step, :steps, :workflow, :run

    def self.step_id(task)
      task
    end

    def initialize(release:, task:, state:, workflow: nil, step: Step.new(id: task), steps: {}, run: nil)
      @release = release
      @workflow = workflow
      @state = state
      @step = step
      @steps = steps.dup.freeze
      @run = run
      freeze
    end

    def record_next_version!(version)
      @state.record_next_version!(version)
    end
  end
end
