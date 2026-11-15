# frozen_string_literal: true

require 'rubygems/package'
require 'digest'

module RubyGemRelease
  module Package
    class Prebuilt
      attr_reader :version

      def initialize(path:, sha256:, name:, version:, platform: 'ruby', audit: nil)
        raise ArgumentError, 'sha256 must be a lowercase SHA256 digest' unless sha256.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(sha256)
        raise ArgumentError, 'path must name an existing archive' unless path.is_a?(String) && !path.empty? && File.file?(path)

        @path = File.expand_path(path)
        @sha256 = sha256
        @name = name
        @version = version
        @platform = platform
        @audit = audit
      end

      def artifact(release)
        raise 'Package version does not match release' unless @version == release.version

        verify_checksum!

        spec = Gem::Package.new(@path).spec
        verify_identity!(spec)
        raise 'Prebuilt artifact filename must match its identity' unless File.basename(@path) == spec.file_name

        @audit&.verify!(@path)
        @path
      end

      def build!(release)
        artifact(release)
      end

      def artifacts(release)
        [artifact(release)]
      end

      def built?(release)
        artifact(release)
        true
      end

      private

      def verify_checksum!
        raise 'Prebuilt artifact changed; refusing publication' unless Digest::SHA256.file(@path).hexdigest == @sha256
      end

      def verify_identity!(spec)
        raise 'Prebuilt artifact identity differs from expectations' unless [spec.name, spec.version.to_s, spec.platform.to_s] == [@name, @version, @platform]
      end
    end
  end
end
