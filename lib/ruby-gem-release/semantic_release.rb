# frozen_string_literal: true

require_relative 'semantic_release/git_history'
require_relative 'semantic_release/conventional_commits'
require_relative 'semantic_release/version_selector'
require_relative 'semantic_release/release_notes'

module RubyGemRelease
  class SemanticRelease
    def initialize(history: GitHistory.new, analyzer: ConventionalCommits.new, selector: VersionSelector.new, notes: ReleaseNotes.new)
      @history = history
      @analyzer = analyzer
      @selector = selector
      @notes = notes
    end

    def analyze(head:, explicit_version: nil)
      explicit_version = nil if explicit_version == ''
      history = @history.read(head: head)
      type = @analyzer.analyze(history.fetch(:commits))
      last_release = history.fetch(:last_release)
      version = @selector.select(last_release: last_release&.fetch('version'), release_type: type, explicit_version: explicit_version)
      notes = @notes.generate(commits: history.fetch(:commits), version: version, last_release: last_release) if version
      Decision.new(head: head, last_release: last_release, commits: history.fetch(:commits),
                   release_type: type, version: version, notes: notes, explicit_version: explicit_version)
    end
  end
end
