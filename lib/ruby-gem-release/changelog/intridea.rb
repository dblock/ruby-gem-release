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

      def update_release(version:, date:)
        validate_release(version, date)
        content = File.read(@path)
        separator = newline(content)
        position = heading(content, UNRELEASED)
        prefix = heading_prefix(content, position)
        check_release_absent(content, version)
        section_end = section_end_position(content, position, prefix.length)
        content[position...section_end] = "#{prefix} #{version} (#{date.strftime('%Y/%m/%d')})" +
                                          remove_placeholder(content[line_end(content, position, separator)...section_end])
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
        check_absent(content, UNRELEASED, 'unreleased heading already exists')

        File.write(@path, content.insert(position, ["#{prefix} #{version} (Next)", '', @placeholder, '', ''].join(separator)))
      end

      def check_release_absent(content, version)
        check_absent(content, %r{\A\#{1,6} #{Regexp.escape(version)} \(\d{4}/\d{2}/\d{2}\)\z}, 'release heading already exists')
      end

      def line_end(content, position, separator)
        content.index(separator, position) || raise(ArgumentError, "heading must end with a newline in #{@path}")
      end

      def section_end_position(content, position, level)
        heading_positions(content, /\A\#{1,6} /, max_level: level).find { |offset| offset > position } || content.length
      end

      def remove_placeholder(section)
        positions = []
        editable_lines(section) { |line, offset| positions << offset if line.chomp == @placeholder }
        raise ArgumentError, "expected exactly one placeholder in #{@path}" unless positions.one?

        position = positions.first
        line_end = section.index("\n", position)
        section.slice!(position, (line_end ? line_end + 1 : section.length) - position)
        section
      end
    end
  end
end
