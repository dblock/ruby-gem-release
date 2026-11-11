# frozen_string_literal: true

require_relative 'source'

module RubyGemRelease
  module Markdown
    class Section
      include Source

      def initialize(path:, heading:)
        raise ArgumentError, 'heading must be a complete Markdown heading line' unless heading.is_a?(String) && /\A\#{1,6}[ \t]+\S[^\r\n]*\z/.match?(heading)

        @path = path
        @pattern = /\A#{Regexp.escape(heading)}\z/
      end

      def validate!
        read_section
        self
      end

      def replace!(body)
        raise ArgumentError, 'section body must be a String' unless body.is_a?(String)

        content, start, finish, separator = read_section
        replacement = replacement_body(body, content, finish, separator)
        File.write(@path, content[0...start] + replacement + content[finish..])
      end

      def gsub!(pattern, replacement)
        content, start, finish, separator = read_section
        body = content[start...finish]
        return unless body.gsub!(pattern, replacement)

        body = substitution_body(body, separator, following: finish < content.length)
        File.write(@path, content[0...start] + body + content[finish..])
      end

      private

      def read_section
        content = File.read(@path)
        separator = newline(content)
        position = heading(content, @pattern)
        finish = section_end_position(content, position, heading_prefix(content, position).length)
        start = content.index(separator, position) || content.length
        [content, start, finish, separator]
      end

      def replacement_body(body, content, finish, separator)
        newline(body)
        text = body.gsub(/\r?\n/, separator).sub(/\A(?:\r?\n)+/, '').sub(/(?:\r?\n)+\z/, '')
        return separator * 2 if text.empty?

        "#{separator}#{separator}#{text}#{trailing_newlines(content, finish, separator)}"
      end

      def substitution_body(body, separator, following:)
        text = body.gsub(/\r?\n/, separator)
        newline(text)
        text.prepend(separator) unless text.empty? || text.start_with?(separator)
        text.concat(separator) if following && !text.end_with?(separator)
        text
      end

      def trailing_newlines(content, finish, separator)
        return separator * 2 if finish < content.length

        content.end_with?(separator) ? separator : ''
      end
    end
  end
end
