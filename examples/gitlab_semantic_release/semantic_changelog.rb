# frozen_string_literal: true

module GitLabSemanticReleaseExample
  class SemanticChangelog
    def release!(_release)
      raise NotImplementedError, 'Load the persisted decision and write its generated release notes'
    end

    def prepare_next!(_release)
      raise NotImplementedError, 'Prepare the changelog for the next development iteration'
    end
  end
end
