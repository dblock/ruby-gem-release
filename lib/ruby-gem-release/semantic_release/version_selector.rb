# frozen_string_literal: true

require_relative 'decision'

module RubyGemRelease
  class SemanticRelease
    class VersionSelector
      def initialize(first_version: '1.0.0')
        validate(first_version)
        @first_version = first_version.dup.freeze
      end

      def select(last_release:, release_type:, explicit_version: nil)
        explicit_version = nil if explicit_version == ''
        validate_options(last_release, release_type, explicit_version)
        version = explicit_version || increment(last_release, release_type)
        raise ArgumentError, 'selected version must exceed the last release' if version && last_release && Gem::Version.new(version) <= Gem::Version.new(last_release)

        version
      end

      private

      def validate_options(last_release, type, explicit)
        validate(last_release) if last_release
        validate(explicit) if explicit
        raise ArgumentError, 'unsupported release type' unless type.nil? || Decision::TYPES.include?(type)
      end

      def increment(version, type)
        return unless type
        return @first_version unless version

        parts = version.split('.').map(&:to_i)
        index = { 'major' => 0, 'minor' => 1, 'patch' => 2 }.fetch(type)
        parts[index] += 1
        ((index + 1)..2).each { |position| parts[position] = 0 }
        parts.join('.')
      end

      def validate(version)
        return if version.is_a?(String) && Version::RubyConstant::PATTERN.match?(version)

        raise ArgumentError, 'semantic versions must be MAJOR.MINOR.PATCH without leading zeros'
      end
    end
  end
end
