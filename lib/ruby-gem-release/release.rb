# frozen_string_literal: true

require 'date'

module RubyGemRelease
  class Release
    attr_reader :version, :previous_version, :next_version, :date, :notes

    def initialize(date:, version:, previous_version:, next_version: nil, notes: nil)
      validate_versions(version, previous_version, next_version)
      validate_metadata(date, notes)

      @version = version.dup.freeze
      @previous_version = previous_version.dup.freeze
      @next_version = next_version&.dup&.freeze
      @date = date.dup.freeze
      @notes = notes&.dup&.freeze
      freeze
    end

    def with_version(version)
      self.class.new(version: version, previous_version: @previous_version, date: @date, next_version: @next_version, notes: @notes)
    end

    def with_next_version(version)
      self.class.new(version: @version, previous_version: @previous_version, date: @date, next_version: version, notes: @notes)
    end

    private

    def validate_metadata(date, notes)
      raise ArgumentError, 'date must be a Date' unless date.instance_of?(Date)
      raise ArgumentError, 'release notes must be a string or nil' unless notes.nil? || notes.is_a?(String)
    end

    def validate_versions(version, previous_version, next_version)
      raise ArgumentError, 'release versions must be strings' unless [version, previous_version].all?(String) && (next_version.nil? || next_version.is_a?(String))
    end
  end
end
