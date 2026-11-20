# frozen_string_literal: true

require_relative 'interface'

module RubyGemRelease
  module Version
    class References
      def initialize(version:, references:)
        raise ArgumentError, 'references must map files to arrays of patterns with a named version capture' unless valid_references?(references)

        @version = Interface.check!(version)
        @references = references
      end

      def read
        @version.read
      end

      def set!(value)
        @version.set!(value)
      end

      def increment!(from: read, **)
        files = reference_files
        files.each { |path, patterns| updated_content(File.read(path), patterns, from) }
        result = @version.increment!(from: from, **)
        files.each do |path, patterns|
          original = File.read(path)
          updated = updated_content(original, patterns, from)
          File.write(path, updated) unless original == updated
        end
        result
      end

      private

      def valid_references?(references)
        references.is_a?(Hash) && references.values.all? do |patterns|
          patterns.is_a?(Array) && patterns.all? { |pattern| pattern.is_a?(Regexp) && pattern.names.include?('version') }
        end
      end

      def reference_files
        @references.each_with_object({}) do |(selector, patterns), files|
          selector = File.path(selector)
          paths = selector.match?(/[*?\[\]{}]/) ? Dir.glob(selector).select { |path| File.file?(path) } : [selector]
          paths.each { |path| (files[File.realpath(path)] ||= []).concat(patterns) }
        end
      end

      def updated_content(content, patterns, version)
        patterns.reduce(content) do |updated, pattern|
          updated.gsub(pattern) { replace_capture(Regexp.last_match, version) }
        end
      end

      def replace_capture(match, version)
        raise ArgumentError, 'version capture did not match' unless match.begin(:version)

        offset = match.begin(:version) - match.begin(0)
        match[0][0...offset] + version + match[0][(offset + match[:version].length)..]
      end
    end
  end
end
