# frozen_string_literal: true

require_relative 'conventional_commits'

module RubyGemRelease
  class SemanticRelease
    class ReleaseNotes
      GROUPS = { 'feat' => 'Features', 'fix' => 'Bug Fixes', 'perf' => 'Performance Improvements' }.freeze

      def generate(commits:, **)
        parsed = ConventionalCommits.new.parsed(commits)
        sections = []
        breaking = breaking_section(parsed)
        sections << breaking if breaking
        sections.concat(change_sections(parsed))
        sections.empty? ? 'Explicit version release.' : sections.join("\n\n")
      end

      private

      def breaking_section(commits)
        notes = commits.flat_map { |commit| commit[:notes] }
        "### Breaking Changes\n\n#{notes.map { |note| "- #{note}" }.join("\n")}" unless notes.empty?
      end

      def change_sections(commits)
        commits.group_by { |commit| GROUPS.fetch(commit[:type], 'Other Changes') }.map do |title, group|
          entries = group.map { |commit| "- #{description(commit)} (#{commit[:sha][0, 7]})" }
          "### #{title}\n\n#{entries.join("\n")}"
        end
      end

      def description(commit)
        subject = commit[:subject].gsub(/([\\`*_\[\]<>])/, '\\\\\1')
        scope = commit[:scope]&.gsub(/([\\`*_\[\]<>])/, '\\\\\1')
        scope ? "**#{scope}:** #{subject}" : subject
      end
    end
  end
end
