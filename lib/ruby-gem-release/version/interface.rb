# frozen_string_literal: true

module RubyGemRelease
  module Version
    module Interface
      METHODS = %i[read set! increment!].freeze

      def self.check!(version)
        missing = METHODS.reject { |name| version.respond_to?(name) }
        raise ArgumentError, "version object must implement #{missing.join(', ')}" unless missing.empty?

        version
      end
    end
  end
end
