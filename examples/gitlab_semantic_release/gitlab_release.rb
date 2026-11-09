# frozen_string_literal: true

module GitLabSemanticReleaseExample
  class GitLabRelease
    def published?(_release, **)
      raise NotImplementedError, 'Verify release metadata and exact asset digests; fail on conflicts'
    end

    def publish!(_release, package:)
      raise NotImplementedError, 'Create a GitLab release using the verified package artifact after the Git push'
    end
  end
end
