# frozen_string_literal: true

require_relative '../version/ruby_constant'
require 'rubygems/version'

module RubyGemRelease
  class SemanticRelease
    class Decision
      ATTRIBUTES = %w[head last_release commits release_type version notes explicit_version].freeze
      TYPES = %w[patch minor major].freeze
      SHA = /\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z/

      attr_reader(*ATTRIBUTES)

      def initialize(head:, last_release:, commits:, release_type:, version:, notes:, explicit_version: nil)
        validate_history(head, last_release, commits)
        validate_selection(last_release, release_type, version, notes, explicit_version)
        values = { 'head' => head, 'last_release' => last_release, 'commits' => commits, 'release_type' => release_type,
                   'version' => version, 'notes' => notes, 'explicit_version' => explicit_version }
        @attributes = immutable_copy(values)
        @attributes.each { |key, value| instance_variable_set("@#{key}", value) }
        freeze
      end

      def self.from_h(attributes)
        raise ArgumentError, 'unsupported semantic decision' unless attributes.is_a?(Hash) && attributes.keys.sort == ATTRIBUTES.sort

        new(**attributes.transform_keys(&:to_sym))
      end

      def to_h
        @attributes
      end

      def release?
        !@version.nil?
      end

      def check!(head:, explicit_version:, version: nil)
        explicit_version = nil if explicit_version == ''
        raise ArgumentError, 'semantic decision belongs to another commit' unless @head == head
        raise ArgumentError, 'explicit version changed after semantic analysis' unless @explicit_version == explicit_version
        raise ArgumentError, 'release version differs from semantic decision' if version && @version != version
      end

      private

      def validate_history(head, last_release, commits)
        raise ArgumentError, 'invalid semantic history head' unless valid_sha?(head)
        raise ArgumentError, 'invalid last semantic release' unless last_release.nil? || valid_last_release?(last_release)

        validate_commits(commits)
      end

      def valid_last_release?(release)
        release.is_a?(Hash) && release.keys.sort == %w[commit tag version] &&
          valid_version?(release['version']) && release['tag'] == "v#{release['version']}" && valid_sha?(release['commit'])
      end

      def validate_commits(commits)
        valid = commits.is_a?(Array) && commits.all? { |commit| valid_commit?(commit) }
        raise ArgumentError, 'invalid semantic commits' unless valid && commits.map { |commit| commit['sha'] }.uniq.size == commits.size
      end

      def valid_commit?(commit)
        commit.is_a?(Hash) && commit.keys.sort == %w[message sha] && valid_sha?(commit['sha']) && commit['message'].is_a?(String)
      end

      def validate_selection(last_release, type, version, notes, explicit)
        raise ArgumentError, 'invalid semantic release type' unless type.nil? || TYPES.include?(type)

        if version.nil?
          validate_skipped_selection(type, notes, explicit)

          return
        end
        validate_selected_version(type, version, notes, explicit)
        return unless last_release && Gem::Version.new(version) <= Gem::Version.new(last_release.fetch('version'))

        raise ArgumentError, 'semantic version must exceed the last release'
      end

      def validate_selected_version(type, version, notes, explicit)
        valid = valid_version?(version) && notes.is_a?(String) && !notes.strip.empty? && [type, explicit].any? &&
                (explicit.nil? || explicit == version)
        raise ArgumentError, 'invalid semantic selection' unless valid
      end

      def validate_skipped_selection(type, notes, explicit)
        raise ArgumentError, 'invalid skipped semantic decision' unless [type, notes, explicit].all?(&:nil?)
      end

      def valid_sha?(value)
        value.is_a?(String) && SHA.match?(value)
      end

      def valid_version?(value)
        value.is_a?(String) && Version::RubyConstant::PATTERN.match?(value)
      end

      def immutable_copy(value)
        case value
        when Hash then value.to_h { |key, entry| [key.dup.freeze, immutable_copy(entry)] }.freeze
        when Array then value.map { |entry| immutable_copy(entry) }.freeze
        when String then value.dup.freeze
        else value
        end
      end
    end
  end
end
