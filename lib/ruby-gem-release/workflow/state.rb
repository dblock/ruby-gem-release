# frozen_string_literal: true

require 'json'
require 'tempfile'
require_relative '../version/ruby_constant'
require_relative '../semantic_release/decision'

module RubyGemRelease
  module Workflow
    class State
      SCHEMAS = { 1 => %w[next_version schema_version].freeze, 2 => %w[analysis next_version schema_version].freeze }.freeze

      def self.create!(directory:)
        file = Tempfile.create(['ruby-gem-release-state-', '.json'], directory)
        file.write(JSON.generate('schema_version' => 2, 'next_version' => nil, 'analysis' => nil))
        file.path
      ensure
        file&.close
      end

      def initialize(path: nil)
        @path = path unless path.to_s.empty?
        @next_version = nil
        @analysis = nil
      end

      def next_version
        return @next_version unless @path

        attributes.fetch('next_version')
      end

      def analysis
        return @analysis unless @path

        value = attributes['analysis']
        SemanticRelease::Decision.from_h(value) if value
      end

      def record_analysis!(decision)
        raise ArgumentError, 'analysis must be a semantic release decision' unless decision.is_a?(SemanticRelease::Decision)
        raise ArgumentError, 'semantic analysis is already recorded' if analysis

        if @path
          persist(attributes.merge('schema_version' => 2, 'analysis' => decision.to_h))
        else
          @analysis = decision
        end
        decision
      end

      def record_next_version!(version)
        validate_version(version)
        if @path
          persist(attributes.merge('next_version' => version))
        else
          @next_version = version.dup.freeze
        end
        version
      end

      private

      def attributes
        values = JSON.parse(File.read(@path))
        valid = values.is_a?(Hash) && SCHEMAS[values['schema_version']] == values.keys.sort
        raise ArgumentError, 'unsupported release state' unless valid

        validate_version(values['next_version']) unless values['next_version'].nil?
        SemanticRelease::Decision.from_h(values['analysis']) unless values['analysis'].nil?
        values
      end

      def persist(values)
        Tempfile.create(['.release-state-', '.json'], File.dirname(@path)) do |file|
          file.write(JSON.generate(values))
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
