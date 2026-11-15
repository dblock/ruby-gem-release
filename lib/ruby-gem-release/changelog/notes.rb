# frozen_string_literal: true

require_relative '../markdown/source'

module RubyGemRelease
  module Changelog
    class Notes
      include Markdown::Source

      def initialize(path: 'CHANGELOG.md', heading: nil, expand_references: false)
        @path = path
        @heading = heading || ->(version) { %r{\A\#{1,6} #{Regexp.escape(version)} \(\d{4}/\d{2}/\d{2}\)\z} }
        @expand_references = expand_references
      end

      def read(version)
        content = File.read(@path)
        position = heading(content, @heading.call(version))
        first = line_end(content, position, newline(content))
        last = section_end_position(content, position, heading_prefix(content, position).length)
        section = content[first...last]
        raise ArgumentError, "empty release notes in #{@path}" unless notes?(document(section))

        @expand_references ? expanded_section(content, first, last).strip : section.strip
      end

      private

      def expanded_section(content, first, last)
        edits = section_edits(content, first, last)
        edits.reverse_each { |range, replacement| content[range] = replacement }
        finish = last + edits.sum { |range, replacement| replacement.length - range.size }
        content[first...finish]
      end

      def section_edits(content, first, last)
        edits = reference_edits(content).select { |range, _replacement| range.begin >= first && range.end <= last }
        edits.reject { |range, _replacement| edits.any? { |other, _value| other != range && other.cover?(range.begin) } }
      end

      def reference_edits(content)
        lines = content.lines
        offsets = line_offsets(lines)
        link_nodes(content).filter_map do |node|
          range = source_range(node, lines, offsets)
          replacement = reference_link(content[range], node)
          [range, replacement] if replacement
        end
      end

      def link_nodes(content)
        nodes = []
        document(content).walk { |node| nodes << node if %i[link image].include?(node.type) }
        nodes
      end

      def source_range(node, lines, offsets)
        position = node.source_position
        start = source_offset(lines, offsets, position.fetch(:start_line), position.fetch(:start_column) - 1)
        finish = source_offset(lines, offsets, position.fetch(:end_line), position.fetch(:end_column))
        start...finish
      end

      def source_offset(lines, offsets, line, column)
        offsets[line - 1] + lines[line - 1].byteslice(0, column).length
      end

      def reference_link(source, node)
        label = source[/\A(!?\[(?:\\.|[^\[\]]|\[[^\]]*\])*\])(?:\[[^\]]*\])?\z/m, 1]
        return unless label

        url = node.url.gsub('&', '&amp;').gsub('<', '%3C').gsub('>', '%3E')
        title = node.title.to_s.empty? ? '' : " #{node.title.dump}"
        "#{label}(<#{url}>#{title})"
      end
    end
  end
end
