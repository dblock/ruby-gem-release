# frozen_string_literal: true

require_relative 'components'

module RubyGemRelease
  module Version
    class RubyConstant
      include Components

      PATTERN = Components::PATTERN

      def initialize(path:, constant:)
        raise ArgumentError, 'constant must be a Ruby constant name' unless constant.is_a?(String) && /\A[A-Z]\w*\z/.match?(constant)

        @path = path
        @assignment = /^([ \t]*#{Regexp.escape(constant)}[ \t]*=[ \t]*)(['"])([^'"\r\n]+)\2/
      end

      def read
        value = assignment(File.read(@path))[3]
        parse(value)
        value
      end

      def set!(value)
        parse(value)
        content = File.read(@path)
        match = assignment(content)
        content[match.begin(3)...match.end(3)] = value
        File.write(@path, content)
        value
      end

      def increment!(part: :patch, from: read)
        set!(next_version(part: part, from: from))
      end

      private

      def assignment(content)
        matches = content.to_enum(:scan, @assignment).map { Regexp.last_match }
        raise ArgumentError, "expected exactly one version assignment in #{@path}" unless matches.one?

        matches.first
      end
    end
  end
end
