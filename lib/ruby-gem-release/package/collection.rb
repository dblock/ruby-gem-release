# frozen_string_literal: true

require 'rubygems/package'

module RubyGemRelease
  module Package
    class Collection
      attr_reader :packages

      def initialize(packages:)
        raise ArgumentError, 'packages must be a nonempty array' unless packages.is_a?(Array) && !packages.empty?

        @packages = packages.dup.freeze
      end

      def version
        versions = @packages.map(&:version).uniq
        raise 'Package collection versions must agree' unless versions.one?

        versions.first
      end

      def artifacts(release)
        paths = @packages.map { |package| package.artifact(release) }
        specs = paths.map { |path| Gem::Package.new(path).spec }
        check_unique!(specs.map(&:full_name), 'package identities')
        check_unique!(paths.map { |path| File.basename(path) }, 'attachment filenames')
        check_versions!(specs, release)

        paths
      end

      def build!(release)
        @packages.each { |package| package.build!(release) }
        artifacts(release)
      end

      def built?(release)
        results = @packages.map { |package| package.built?(release) }
        return false unless results.all?

        artifacts(release)
        true
      end

      private

      def check_versions!(specs, release)
        raise 'Package collection versions must match release' unless specs.all? { |spec| spec.version.to_s == release.version }
      end

      def check_unique!(values, label)
        raise "Duplicate #{label} are not allowed" unless values.uniq == values
      end
    end
  end
end
