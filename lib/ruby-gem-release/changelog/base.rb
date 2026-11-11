# frozen_string_literal: true

require 'date'
require_relative '../markdown/source'

module RubyGemRelease
  module Changelog
    class Base
      include Markdown::Source

      def initialize(path: 'CHANGELOG.md')
        @path = path
      end

      def release!(release)
        validate_release(release.version, release.date)
        return if released?(release.version)

        update_release(version: release.version, date: release.date)
      end

      def released?(version)
        validate_version(version)
        return false unless File.file?(@path)

        matches = heading_positions(File.read(@path), release_pattern(version))
        raise ArgumentError, "duplicate release headings in #{@path}" if matches.size > 1

        matches.one?
      end

      def prepare_next!(release)
        update_next(version: release.next_version, released_version: release.version)
      end

      def pending?
        content = File.read(@path)
        notes?(document(unreleased_notes(content, newline(content))))
      end

      private

      def unreleased_notes(content, separator)
        position = heading(content, self.class::UNRELEASED)
        section_end = section_end_position(content, position, heading_prefix(content, position).length)
        content[line_end(content, position, separator)...section_end]
      end

      def check_release_notes(content, position, separator, version)
        section_end = section_end_position(content, position, heading_prefix(content, position).length)
        check_notes(content[line_end(content, position, separator)...section_end], version)
      end

      def check_notes(section, version)
        return section if notes?(document(section))

        raise ArgumentError, "cannot release #{version}: empty release notes in #{@path}; add release notes before retrying"
      end

      def notes?(node)
        return false if %i[heading html_block html_inline].include?(node.type)
        return !node.string_content.strip.empty? if %i[text code code_block].include?(node.type)

        node.each.any? { |child| notes?(child) }
      end

      def editable_lines(content)
        excluded = excluded_lines(content)
        offset = 0
        content.each_line.with_index(1) do |line, number|
          yield line, offset unless excluded.include?(number)
          offset += line.length
        end
      end

      def excluded_lines(content)
        excluded = Set.new
        document(content).walk do |node|
          next unless %i[code_block html_block block_quote].include?(node.type)

          position = node.source_position
          excluded.merge(position[:start_line]..position[:end_line])
        end
        excluded
      end

      def validate_version(version)
        raise ArgumentError, "invalid version: #{version.inspect}" unless version.is_a?(String) && /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/.match?(version)
      end

      def validate_release(version, date)
        validate_version(version)
        raise ArgumentError, 'date must be a Date' unless date.instance_of?(Date)
      end

      def check_absent(content, pattern, message)
        raise ArgumentError, "#{message} in #{@path}" unless heading_positions(content, pattern).empty?
      end
    end
  end
end
