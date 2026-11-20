# frozen_string_literal: true

module RubyGemRelease
  module Version
    module Components
      PATTERN = /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/

      def next_version(part: :patch, from: read)
        parts = parse(from)
        index = { 'major' => 0, 'minor' => 1, 'patch' => 2 }.fetch(part.to_s) do
          raise ArgumentError, 'bump part must be major, minor, or patch'
        end
        parts[index] += 1
        ((index + 1)...parts.size).each { |i| parts[i] = 0 }
        parts.join('.')
      end

      private

      def parse(value)
        match = PATTERN.match(value) if value.is_a?(String)
        raise ArgumentError, "invalid version: #{value.inspect}; expected MAJOR.MINOR.PATCH" unless match

        match.captures.map(&:to_i)
      end
    end
  end
end
