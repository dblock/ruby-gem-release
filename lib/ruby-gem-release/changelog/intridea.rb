# frozen_string_literal: true

module RubyGemRelease
  module Changelog
    class Intridea < Base
      UNRELEASED = /\A\#{1,6} \d+\.\d+\.\d+ \(Next\)\z/
      PLACEHOLDER = '- Your contribution here.'

      def initialize(path: 'CHANGELOG.md', placeholder: PLACEHOLDER)
        raise ArgumentError, 'placeholder must be a single nonempty line' unless placeholder.is_a?(String) && !placeholder.empty? && !placeholder.match?(/[\r\n]/)

        super(path: path)
        @placeholder = placeholder
      end

      private

      def unreleased_notes(content, separator)
        remove_placeholder(super, separator)
      end

      def update_release(version:, date:)
        validate_release(version, date)
        content = File.read(@path)
        separator = newline(content)
        position = heading(content, UNRELEASED)
        prefix = heading_prefix(content, position)
        check_release_absent(content, version)
        section_end = section_end_position(content, position, prefix.length)
        content[position...section_end] = "#{prefix} #{version} (#{date.strftime('%Y/%m/%d')})" +
                                          release_notes(content[line_end(content, position, separator)...section_end], separator, version)
        File.write(@path, content)
      end

      def update_next(version:, released_version:)
        validate_version(version)
        validate_version(released_version)
        content = File.read(@path)
        separator = newline(content)
        pattern = %r{\A\#{1,6} #{Regexp.escape(released_version)} \(\d{4}/\d{2}/\d{2}\)\z}
        position = heading(content, pattern)
        prefix = heading_prefix(content, position)
        return if heading_positions(content, /\A\#{1,6} #{Regexp.escape(version)} \(Next\)\z/).one?

        check_absent(content, UNRELEASED, 'unreleased heading already exists')
        write_next_section(content, position, prefix, version, separator)
      end

      def write_next_section(content, position, prefix, version, separator)
        subsections = subsection_headings(content, position, prefix.length)
        File.write(@path, content.insert(position, build_next_section(prefix, version, subsections, separator)))
      end

      def check_release_absent(content, version)
        check_absent(content, release_pattern(version), 'release heading already exists')
      end

      def release_pattern(version)
        %r{\A\#{1,6} #{Regexp.escape(version)} \(\d{4}/\d{2}/\d{2}\)\z}
      end

      def release_notes(section, separator, version)
        check_notes(remove_placeholder(section, separator), version)
      end

      def remove_placeholder(section, separator)
        positions = []
        editable_lines(section) { |line, offset| positions << offset if line.chomp == @placeholder }
        raise ArgumentError, "expected at least one placeholder in #{@path}" if positions.empty?

        positions.reverse_each { |position| section.slice!(position, placeholder_length(section, position, separator)) }
        section
      end

      def subsection_headings(content, position, level)
        section_end = section_end_position(content, position, level)
        lines = content.lines
        offsets = line_offsets(lines)
        subsection_heading_lines(content, level).filter_map do |index|
          lines[index].chomp if (position...section_end).cover?(offsets[index])
        end
      end

      def subsection_heading_lines(content, level)
        document(content).each.filter_map do |node|
          node.source_position[:start_line] - 1 if node.type == :heading && node.header_level == level + 1
        end
      end

      def build_next_section(prefix, version, subsections, separator)
        lines = ["#{prefix} #{version} (Next)"]
        if subsections.empty?
          lines.push('', @placeholder, '', '')
        else
          subsections.each { |subsection| lines.push('', subsection, '', @placeholder) }
          lines.push('', '')
        end
        lines.join(separator)
      end

      def placeholder_length(section, position, separator)
        line_end = section.index("\n", position)
        length = (line_end ? line_end + 1 : section.length) - position
        length += separator.length if section[0...position].end_with?(separator * 2) && section[position + length, separator.length] == separator
        length
      end
    end
  end
end
