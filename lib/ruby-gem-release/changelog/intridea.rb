# frozen_string_literal: true

module RubyGemRelease
  module Changelog
    class Intridea < Base
      UNRELEASED = /\A\#{1,6} \d+\.\d+\.\d+ \(Next\)\z/
      PLACEHOLDER = '- Your contribution here.'
      DATE_FORMAT = '%Y/%m/%d'

      def initialize(path: 'CHANGELOG.md', placeholder: PLACEHOLDER, date_format: DATE_FORMAT, sections: [])
        raise ArgumentError, 'placeholder must be a single nonempty line' unless placeholder.is_a?(String) && !placeholder.empty? && !placeholder.match?(/[\r\n]/)
        raise ArgumentError, 'date_format must be a nonempty single-line strftime string or a callable' unless valid_date_format?(date_format)

        validate_sections(sections)
        super(path: path)
        @placeholder = placeholder
        @date_format = date_format
        @sections = sections.dup
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
        content[position...section_end] = released_section(content[line_end(content, position, separator)...section_end], prefix, version, date, separator)
        File.write(@path, content)
      end

      def released_section(notes, prefix, version, date, separator)
        release_heading(prefix, version, date) + release_notes(notes, separator, version, prefix.length)
      end

      # Checked before writing, so a date_format that produces an unrecognizable heading leaves the file unchanged.
      def release_heading(prefix, version, date)
        heading = "#{prefix} #{version} (#{format_date(date)})"
        raise ArgumentError, "date_format produced an invalid release heading: #{heading.inspect}" unless release_pattern(version).match?(heading)

        heading
      end

      def update_next(version:, released_version:)
        validate_version(version)
        validate_version(released_version)
        content = File.read(@path)
        separator = newline(content)
        position = heading(content, release_pattern(released_version))
        prefix = heading_prefix(content, position)
        return if heading_positions(content, /\A\#{1,6} #{Regexp.escape(version)} \(Next\)\z/).one?

        check_absent(content, UNRELEASED, 'unreleased heading already exists')
        write_next_section(content, position, prefix, version, separator)
      end

      # Configured sections start every development section, including ones the
      # previous release dropped because they had no notes.
      def write_next_section(content, position, prefix, version, separator)
        File.write(@path, content.insert(position, build_next_section(prefix, version, next_subsections(content, position, prefix), separator)))
      end

      def next_subsections(content, position, prefix)
        return subsection_headings(content, position, prefix.length) if @sections.empty?
        raise ArgumentError, 'section headings cannot be deeper than level six' if prefix.length == 6

        @sections.map { |name| "#{prefix}# #{name}" }
      end

      def check_release_absent(content, version)
        check_absent(content, release_pattern(version), 'release heading already exists')
      end

      # Matches a parenthesized heading with a digit, so a date in any format counts as released while (Next) and other words do not.
      def release_pattern(version)
        /\A\#{1,6} #{Regexp.escape(version)} \((?!Next\))[^\r\n]*\d[^\r\n]*\)\z/
      end

      def format_date(date)
        formatted = @date_format.respond_to?(:call) ? @date_format.call(date) : date.strftime(@date_format)
        raise ArgumentError, "date_format must return a String, got #{formatted.class}" unless formatted.is_a?(String)

        formatted
      end

      def valid_date_format?(date_format)
        return true if date_format.respond_to?(:call)

        date_format.is_a?(String) && !date_format.empty? && !date_format.match?(/[\r\n]/)
      end

      def release_notes(section, separator, version, level)
        remove_placeholder(section, separator)
        remove_empty_categories(section, separator, level) if @sections.any?
        check_notes(section, version)
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
