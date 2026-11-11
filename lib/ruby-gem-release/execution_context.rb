# frozen_string_literal: true

require_relative 'execution_context/step'
require_relative 'release'

module RubyGemRelease
  class ExecutionContext
    attr_reader :release, :step, :steps, :workflow, :run, :analysis, :stage, :hook, :hook_index, :failure

    def self.step_id(task)
      task
    end

    def initialize(release:, task:, state:, workflow: nil, step: Step.new(id: task), steps: {}, run: nil, analysis: state&.analysis)
      @release = release
      @workflow = workflow
      @state = state
      @step = step
      @steps = steps.dup.freeze
      @run = run
      @analysis = analysis
      freeze
    end

    def record_next_version!(version)
      @state.record_next_version!(version)
    end

    def record_analysis!(decision)
      @state.record_analysis!(decision)
    end

    def with(release: @release, analysis: @analysis, stage: nil, hook: nil, hook_index: nil, failure: @failure)
      copy = dup
      { release: release, analysis: analysis, stage: stage, hook: hook, hook_index: hook_index, failure: failure }.each do |name, value|
        copy.instance_variable_set("@#{name}", value)
      end
      copy.freeze
    end

    def refresh
      snapshot = @state.snapshot
      analysis = snapshot.fetch(:analysis)
      release = if @release
                  Release.new(version: analysis&.version || @release.version, gemspec_version: @release.gemspec_version, date: @release.date,
                              next_version: snapshot.fetch(:next_version), notes: analysis&.notes || @release.notes)
                end
      with(release: release, analysis: analysis)
    end
  end
end
