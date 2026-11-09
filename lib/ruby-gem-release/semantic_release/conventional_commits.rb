# frozen_string_literal: true

require_relative 'decision'

module RubyGemRelease
  class SemanticRelease
    class ConventionalCommits
      SELECTORS = %i[type scope subject breaking revert].freeze

      def initialize(rules: [])
        @rules = rules.map do |rule|
          validate_rule(rule)
          rule.to_h { |key, value| [key, value.is_a?(String) ? value.dup.freeze : value] }.freeze
        end.freeze
      end

      def analyze(commits)
        parsed(commits).filter_map { |commit| release_type(commit) }.max_by { |type| Decision::TYPES.index(type) }
      end

      def parsed(commits)
        parsed = commits.reject { |commit| commit.fetch('message').strip.empty? }.map { |commit| parse(commit) }
        cancelled = []
        parsed.reverse_each do |commit|
          next if cancelled.include?(commit) || !commit[:revert]

          original = reverted_original(parsed, commit, cancelled)
          cancelled.push(commit, original) if original
        end
        parsed - cancelled
      end

      private

      def reverted_original(commits, revert, cancelled)
        commits.find { |commit| commit != revert && commit[:sha].start_with?(revert[:revert]) && !cancelled.include?(commit) }
      end

      def parse(commit)
        message = commit.fetch('message')
        attributes = parsed_header(message.lines(chomp: true).first.to_s)
        notes = breaking_notes(message)
        notes << attributes[:subject] if attributes[:breaking] && notes.empty?
        attributes.merge(sha: commit.fetch('sha'), notes: notes, breaking: attributes[:breaking] || !notes.empty?,
                         revert: message[/^This reverts commit ([0-9a-f]{7,64})\./i, 1])
      end

      def parsed_header(header)
        match = /\A([A-Za-z0-9_-]+)(?:\(([^()\r\n]+)\))?(!)?: (.+)\z/.match(header)
        return { type: nil, scope: nil, subject: header, breaking: false } unless match

        { type: match[1], scope: match[2], subject: match[4], breaking: match[3] == '!' }
      end

      def breaking_notes(message)
        message.split(/^(?=BREAKING(?: CHANGE|-CHANGE):|[A-Za-z][A-Za-z-]*(?:: | #))/).filter_map do |section|
          match = /\ABREAKING(?: CHANGE|-CHANGE):[ \t]*(.*)/m.match(section)
          match[1].strip if match
        end
      end

      def release_type(commit)
        matches = @rules.select { |rule| matches?(commit, rule) }
        return default_type(commit) if matches.empty?

        matches.filter_map { |rule| rule[:release].to_s unless rule[:release] == false }.max_by { |type| Decision::TYPES.index(type) }
      end

      def default_type(commit)
        return 'major' if commit[:breaking]
        return 'minor' if commit[:type] == 'feat'
        return 'patch' if commit[:revert] || %w[fix perf].include?(commit[:type])

        nil
      end

      def matches?(commit, rule)
        rule.all? do |key, value|
          next true if key == :release
          next value ? commit[key] : !commit[key] if %i[breaking revert].include?(key)

          commit[key].is_a?(String) && File.fnmatch?(value, commit[key])
        end
      end

      def validate_rule(rule)
        valid = rule.is_a?(Hash) && (rule.keys - [*SELECTORS, :release]).empty? && rule.key?(:release) &&
                (rule[:release] == false || Decision::TYPES.include?(rule[:release].to_s))
        raise ArgumentError, 'release rules require supported selectors and major, minor, patch, or false' unless valid

        validate_selectors(rule.except(:release))
      end

      def validate_selectors(selectors)
        selectors.each do |key, value|
          valid = %i[breaking revert].include?(key) ? [true, false].include?(value) : value.is_a?(String)
          raise ArgumentError, "invalid release rule selector: #{key}" unless valid
        end
      end
    end
  end
end
