# frozen_string_literal: true

require 'ruby-gem-release/execution_provider'

module GitLabSemanticReleaseExample
  class GitLab < RubyGemRelease::ExecutionProvider
    def ref
      raise NotImplementedError, 'Map GitLab branch metadata to a full Git ref'
    end

    def export(_values)
      raise NotImplementedError, 'Update the current environment and persist exports for subsequent processes'
    end

    def output(_values)
      raise NotImplementedError, 'Transport release decisions to the GitLab pipeline'
    end

    def context(**)
      raise NotImplementedError, 'Construct execution snapshots from GitLab job metadata'
    end

    def step_id(_task)
      raise NotImplementedError, 'Identify the current GitLab release phase'
    end

    def failed_steps
      raise NotImplementedError, 'Report failed GitLab release phases'
    end

    def oidc_token(audience:)
      raise NotImplementedError, "Acquire a GitLab identity token for #{audience}"
    end

    def mask(_value)
      raise NotImplementedError, 'Provide safe GitLab secret handling without logging the secret'
    end
  end
end
