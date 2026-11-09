# frozen_string_literal: true

require 'open3'
require 'tempfile'

module RubyGemRelease
  module Hosting
    class GitHubRelease
      def initialize(repository: nil)
        repository ||= ENV.fetch('GITHUB_REPOSITORY', nil)
        raise ArgumentError, 'repository must be OWNER/REPO' unless repository.nil? || (repository.is_a?(String) && %r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z}.match?(repository))

        @repository = repository
      end

      def publish!(release, package: nil, artifacts: [])
        version = release.version
        raise ArgumentError, 'release version must be MAJOR.MINOR.PATCH' unless version.is_a?(String) && /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/.match?(version)

        tag = "v#{version}"
        paths = artifact_paths(package ? [package.artifact(release)] : artifacts)
        output, error, status = create_release(tag, paths, release.notes)
        raise "GitHub Release creation failed: #{error.strip}" unless status.success?

        output.strip
      end

      private

      def create_release(tag, paths, notes)
        return Open3.capture3(*command(tag), '--generate-notes', *paths) if notes.nil?

        raise ArgumentError, 'release notes must not be empty' if notes.strip.empty?

        Tempfile.create(['ruby-gem-release-notes-', '.md']) do |file|
          file.write(notes)
          file.close
          Open3.capture3(*command(tag), '--notes-file', file.path, *paths)
        end
      end

      def command(tag)
        arguments = ['gh', 'release', 'create', tag]
        arguments.push('--repo', @repository) if @repository
        arguments.push('--verify-tag', '--title', tag)
      end

      def artifact_paths(artifacts)
        raise ArgumentError, 'artifacts must be an array of file paths' unless artifacts.is_a?(Array)

        artifacts.map do |path|
          raise ArgumentError, 'artifact must name an existing file without # or line breaks' unless path.is_a?(String) && !path.match?(/[#\r\n]/) && File.file?(path)

          File.expand_path(path)
        end
      end
    end
  end
end
