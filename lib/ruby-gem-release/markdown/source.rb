# frozen_string_literal: true

require 'commonmarker'

module RubyGemRelease
  module Markdown
    module Source
      private

      def heading(content, pattern)
        matches = heading_positions(content, pattern)
        raise ArgumentError, "expected exactly one matching heading in #{@path}" unless matches.one?

        matches.first
      end

      def heading_positions(content, pattern, max_level: 6)
        lines = content.lines
        offsets = line_offsets(lines)
        matches = []
        document(content).each do |node|
          next unless node.type == :heading && node.header_level <= max_level

          index = node.source_position[:start_line] - 1
          matches << offsets[index] if pattern.match?(lines[index].chomp)
        end
        matches
      end

      def heading_prefix(content, position)
        content[position, 6][/\A#+/]
      end

      def section_end_position(content, position, level)
        heading_positions(content, /\A/, max_level: level).find { |offset| offset > position } || content.length
      end

      def line_end(content, position, separator)
        content.index(separator, position) || raise(ArgumentError, "heading must end with a newline in #{@path}")
      end

      def document(content)
        Commonmarker.parse(content, options: { extension: { shortcodes: false } })
      end

      def line_offsets(lines)
        offset = 0
        lines.map do |line|
          position = offset
          offset += line.length
          position
        end
      end

      def newline(content)
        raise ArgumentError, "mixed or unsupported line endings in #{@path}" if (content.match?(/(?<!\r)\n/) && content.include?("\r\n")) || content.match?(/\r(?!\n)/)

        content.include?("\r\n") ? "\r\n" : "\n"
      end
    end
  end
end
