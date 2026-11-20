# frozen_string_literal: true

require_relative 'components'

module RubyGemRelease
  module Version
    class PlainText
      include Components

      LINE_ENDING = /\r?\n\z/

      def initialize(path: 'VERSION')
        @path = path
      end

      def read
        version_in(File.read(@path))
      end

      def set!(value)
        parse(value)
        original = File.read(@path)
        version_in(original)
        File.write(@path, "#{value}#{original[LINE_ENDING]}")
        value
      end

      def increment!(part: :patch, from: read)
        set!(next_version(part: part, from: from))
      end

      private

      def version_in(content)
        content.sub(LINE_ENDING, '').tap { |value| parse(value) }
      end
    end
  end
end
