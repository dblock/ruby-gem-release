# frozen_string_literal: true

module RubyGemRelease
  module Changelog
    class KeepAChangelog < Base
      UNRELEASED = /\A\#{1,6} \[Unreleased\]\z/

      def initialize(path: 'CHANGELOG.md', placeholder: nil, sections: [])
        validate_template(placeholder, sections)
        super(path: path)
        @placeholder = placeholder
        @sections = sections.dup
      end

      private

      def validate_template(placeholder, sections)
        raise ArgumentError, 'placeholder must be a single nonempty line' unless placeholder.nil? || single_line?(placeholder)
        raise ArgumentError, 'sections must be an array of unique nonempty names' unless sections.is_a?(Array) && sections.all? { |name| single_line?(name) } && sections.uniq == sections
      end

      def single_line?(value)
        value.is_a?(String) && !value.strip.empty? && !value.match?(/[\r\n]/)
      end

      def release_pattern(version)
        /\A\#{1,6} \[#{Regexp.escape(version)}\] - \d{4}-\d{2}-\d{2}\z/
      end

      def unreleased_notes(content, separator)
        reference = unreleased_reference(content)
        comparison(reference[2]) if reference
        clean_notes(super, separator, heading_prefix(content, heading(content, UNRELEASED)).length)
      end

      def update_release(version:, date:)
        validate_release(version, date)
        content = File.read(@path)
        separator = newline(content)
        position = heading(content, UNRELEASED)
        check_absent(content, /\A\#{1,6} \[#{Regexp.escape(version)}\] - \d{4}-\d{2}-\d{2}\z/, 'release heading already exists')
        clean_release_section(content, position, separator)
        content[position...line_end(content, position, separator)] = "#{heading_prefix(content, position)} [#{version}] - #{date.strftime('%Y-%m-%d')}"
        release_references(content, version, separator)
        check_release_notes(content, position, separator, version)
        File.write(@path, content)
      end

      def update_next(version:, released_version:)
        validate_version(version)
        validate_version(released_version)
        content = File.read(@path)
        separator = newline(content)
        position = heading(content, release_pattern(released_version))
        prefix = heading_prefix(content, position)
        check_next_reference(content, released_version)
        return if heading_positions(content, UNRELEASED).one?

        check_absent(content, UNRELEASED, 'duplicate unreleased headings')

        File.write(@path, content.insert(position, next_section(prefix, separator)))
      end

      def clean_release_section(content, position, separator)
        level = heading_prefix(content, position).length
        start = line_end(content, position, separator)
        finish = section_end_position(content, position, level)
        content[start...finish] = clean_notes(content[start...finish], separator, level)
      end

      def clean_notes(section, separator, level)
        return section unless @placeholder || @sections.any?

        positions = []
        editable_lines(section) { |line, offset| positions << offset if @placeholder && line.chomp == @placeholder }
        positions.reverse_each { |offset| remove_line(section, offset, separator) }
        remove_empty_categories(section, separator, level)
        section
      end

      def remove_empty_categories(section, separator, level)
        heading_positions(section, /\A\#{#{level + 1}} /).reverse_each do |offset|
          finish = section_end_position(section, offset, level + 1)
          start = section.index(separator, offset) || section.length
          remove_line(section, offset, separator) unless notes?(document(section[start...finish]))
        end
      end

      def remove_line(section, offset, separator)
        finish = section.index(separator, offset)
        length = (finish ? finish + separator.length : section.length) - offset
        length += separator.length if section[0...offset].end_with?(separator * 2) && section[offset + length, separator.length] == separator
        section.slice!(offset, length)
      end

      def next_section(prefix, separator)
        raise ArgumentError, 'category headings cannot be deeper than level six' if prefix.length == 6 && @sections.any?

        lines = ["#{prefix} [Unreleased]", '']
        if @sections.empty?
          lines.push(@placeholder, '') if @placeholder
        else
          @sections.each { |name| lines.push("#{prefix}# #{name}", '').concat(@placeholder ? [@placeholder, ''] : []) }
        end
        lines.push('').join(separator)
      end

      def references(content, label)
        return [] unless reference_defined?(content, label)

        pattern = /\A[ \t]{0,3}\[#{Regexp.escape(label)}\]:[ \t]*(.*)\z/i
        matches = []
        editable_lines(content) do |line, offset|
          match = pattern.match(line.chomp)
          matches << [offset, line.chomp, match[1]] if match
        end
        matches
      end

      def reference_defined?(content, label)
        node = document("#{content}\n\n[#{label}]\n").last_child.first_child
        node&.type == :link
      end

      def unreleased_reference(content)
        matches = references(content, 'Unreleased')
        raise ArgumentError, 'duplicate Unreleased reference links' if matches.size > 1

        matches.first
      end

      def comparison(url)
        match = %r{\A(https?://[^\s<>]+/compare/)([^/\s]*?)(\d+\.\d+\.\d+)\.\.\.([^\s<>]+)\z}.match(url)
        raise ArgumentError, 'Unreleased reference must be a comparison URL ending in VERSION...BRANCH' unless match

        match
      end

      def release_references(content, version, separator)
        reference = unreleased_reference(content)
        return unless reference

        raise ArgumentError, 'release reference already exists' unless references(content, version).empty?

        offset, line, url = reference
        match = comparison(url)
        updated = "[Unreleased]: #{match[1]}#{match[2]}#{version}...#{match[4]}"
        released = "[#{version}]: #{match[1]}#{match[2]}#{match[3]}...#{match[2]}#{version}"
        content[offset, line.length] = "#{updated}#{separator}#{released}"
      end

      def check_next_reference(content, released_version)
        reference = unreleased_reference(content)
        return unless reference

        match = comparison(reference[2])
        raise ArgumentError, 'Unreleased comparison must start at the released version' unless match[3] == released_version
      end
    end
  end
end
