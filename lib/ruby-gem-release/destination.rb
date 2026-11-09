# frozen_string_literal: true

module RubyGemRelease
  class Destination
    def check_version!(name:, version:)
      raise NotImplementedError, "#{self.class} must implement check_version!"
    end

    def publish!(release, package:)
      raise NotImplementedError, "#{self.class} must implement publish!"
    end

    def authentication
      nil
    end
  end
end
