# frozen_string_literal: true

require_relative '../../execution_context'

module RubyGemRelease
  class ExecutionContext
    class GitHub < ExecutionContext
      class Run
        attr_reader :repository, :ref, :sha, :run_id, :run_attempt, :job_id, :workflow_name, :workflow_ref

        def initialize(environment: ENV)
          @repository = value(environment, 'GITHUB_REPOSITORY')
          @ref = value(environment, 'GITHUB_REF')
          @sha = value(environment, 'GITHUB_SHA')
          @run_id = value(environment, 'GITHUB_RUN_ID')
          @run_attempt = value(environment, 'GITHUB_RUN_ATTEMPT')
          @job_id = value(environment, 'GITHUB_JOB')
          @workflow_name = value(environment, 'GITHUB_WORKFLOW')
          @workflow_ref = value(environment, 'GITHUB_WORKFLOW_REF')
          freeze
        end

        private

        def value(environment, name)
          environment[name]&.dup&.freeze
        end
      end
    end
  end
end
