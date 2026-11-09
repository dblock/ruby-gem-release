# frozen_string_literal: true

require_relative 'base'

module RubyGemRelease
  module Changelog
    class Generated < Base
      def release!(release)
        check_generated_notes(release)
        content = File.exist?(@path) ? File.read(@path) : "# Changelog\n"
        separator = newline(content)
        check_absent(content, /\A## #{Regexp.escape(release.version)}(?: |\z)/, 'release already exists')
        File.write(@path, insert_release(content, release, separator))
      end

      def prepare_next!(_release); end

      private

      def check_generated_notes(release)
        validate_release(release.version, release.date)
        raise ArgumentError, 'generated release notes are required' unless release.notes.is_a?(String)

        check_notes(release.notes, release.version)
      end

      def insert_release(content, release, separator)
        sections = heading_positions(content, /\A## /, max_level: 2)
        position = sections.first || content.length
        entry = "## #{release.version} (#{release.date.strftime('%Y/%m/%d')})\n\n#{release.notes.strip}\n\n".gsub("\n", separator)
        prefix = content[...position].sub(/(?:\r?\n)*\z/, "#{separator}#{separator}")
        prefix + entry + content[position..]
      end
    end
  end
end
