# frozen_string_literal: true

require_relative 'ruby_constant'

module RubyGemRelease
  module Version
    class References < RubyConstant
      def initialize(references:, **)
        super(**)
        raise ArgumentError, 'references must map files to arrays of patterns with a named version capture' unless references.is_a?(Hash) && references.values.all? { |patterns| patterns.is_a?(Array) && patterns.all? { |pattern| pattern.is_a?(Regexp) && pattern.names.include?('version') } }

        @references = references
      end

      def increment!(part: :patch, from: read)
        next_version(part: part, from: from)
        updates = reference_files.map { |path, patterns| updated_file(path, patterns, from) }
        result = super
        updates.each { |path, original, updated| File.write(path, updated) unless original == updated }
        result
      end

      private

      def reference_files
        @references.each_with_object({}) do |(selector, patterns), files|
          selector = File.path(selector)
          paths = selector.match?(/[*?\[\]{}]/) ? Dir.glob(selector).select { |path| File.file?(path) } : [selector]
          paths.each { |path| (files[File.realpath(path)] ||= []).concat(patterns) }
        end
      end

      def updated_file(path, patterns, version)
        original = File.read(path)
        updated = patterns.reduce(original) do |content, pattern|
          content.gsub(pattern) { replace_capture(Regexp.last_match, version) }
        end
        [path, original, updated]
      end

      def replace_capture(match, version)
        raise ArgumentError, 'version capture did not match' unless match.begin(:version)

        offset = match.begin(:version) - match.begin(0)
        match[0][0...offset] + version + match[0][(offset + match[:version].length)..]
      end
    end
  end
end
