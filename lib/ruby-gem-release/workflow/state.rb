# frozen_string_literal: true

require 'json'
require 'tempfile'
require_relative '../version/ruby_constant'

module RubyGemRelease
  module Workflow
    class State
      def self.create!(directory:)
        file = Tempfile.create(['ruby-gem-release-state-', '.json'], directory)
        file.write(JSON.generate('schema_version' => 1, 'next_version' => nil))
        file.path
      ensure
        file&.close
      end

      def initialize(path: nil)
        @path = path unless path.to_s.empty?
        @next_version = nil
      end

      def next_version
        return @next_version unless @path

        attributes = JSON.parse(File.read(@path))
        valid = attributes.is_a?(Hash) && attributes.keys.sort == %w[next_version schema_version] && attributes['schema_version'] == 1
        raise ArgumentError, 'unsupported release state' unless valid

        value = attributes.fetch('next_version')
        validate_version(value) unless value.nil?
        value
      end

      def record_next_version!(version)
        validate_version(version)
        if @path
          next_version
          persist(version)
        else
          @next_version = version.dup.freeze
        end
        version
      end

      private

      def persist(version)
        Tempfile.create(['.release-state-', '.json'], File.dirname(@path)) do |file|
          file.write(JSON.generate('schema_version' => 1, 'next_version' => version))
          file.close
          File.rename(file.path, @path)
        end
      end

      def validate_version(version)
        return if version.is_a?(String) && Version::RubyConstant::PATTERN.match?(version)

        raise ArgumentError, 'next version must be MAJOR.MINOR.PATCH'
      end
    end
  end
end
