# frozen_string_literal: true

require 'digest'
require 'fileutils'
require_relative '../destination'

module RubyGemRelease
  module RSpec
    module Publication
      def publish!(release, package:)
        return if published?(release, package: package)
        raise @failure if @failure

        FileUtils.mkdir_p(@directory)
        FileUtils.cp(package.artifact(release), publication_path(release))
      end

      def published?(release, package:)
        path = publication_path(release)
        return false unless File.file?(path)
        raise 'Published checksum differs' unless Digest::SHA256.file(path).hexdigest == Digest::SHA256.file(package.artifact(release)).hexdigest

        true
      end

      private

      def publication_path(release)
        File.join(@directory, "#{release.version}.gem")
      end
    end

    class Destination < RubyGemRelease::Destination
      include Publication

      def initialize(directory: ENV.fetch('RELEASE_DATA_DIR'), failure: nil)
        super()
        @directory = File.join(directory, 'registry')
        @failure = failure
      end
    end

    class Hosting
      include Publication

      def initialize(directory: ENV.fetch('RELEASE_DATA_DIR'), failure: nil)
        @directory = File.join(directory, 'hosting')
        @failure = failure
      end
    end
  end
end
