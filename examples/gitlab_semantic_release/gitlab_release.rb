# frozen_string_literal: true

module GitLabSemanticReleaseExample
  class GitLabRelease
    def publish!(_release, package:)
      raise NotImplementedError, 'Verify or update GitLab metadata and exact assets after the Git push; fail on immutable conflicts'
    end
  end
end
