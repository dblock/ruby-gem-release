# frozen_string_literal: true

require 'open3'
require 'tempfile'
require_relative 'github_release/existing'

module RubyGemRelease
  module Hosting
    class GitHubRelease
      def initialize(repository: nil)
        repository ||= ENV.fetch('GITHUB_REPOSITORY', nil)
        raise ArgumentError, 'repository must be OWNER/REPO' unless repository.nil? || (repository.is_a?(String) && %r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z}.match?(repository))

        @repository = repository
      end

      def publish!(release, package: nil, artifacts: [])
        paths = release_paths(release, package, artifacts)
        existing = Existing.new(repository: @repository)
        missing = existing.missing(release, paths)
        return upload_missing(release, existing, missing) if existing.exists?

        tag = "v#{release.version}"
        output, error, status = create_release(tag, paths, release.notes)
        raise "GitHub Release creation failed: #{error.strip}" unless status.success?

        output.strip
      end

      private

      def release_paths(release, package, artifacts)
        version = release.version
        raise ArgumentError, 'release version must be MAJOR.MINOR.PATCH' unless version.is_a?(String) && /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/.match?(version)
        raise ArgumentError, 'release notes must not be empty' if release.notes && release.notes.strip.empty?

        artifact_paths(package ? [package.artifact(release)] : artifacts)
      end

      def upload_missing(release, existing, paths)
        edit_release(release) if existing.changed?(release)
        unless paths.empty?
          command = ['gh', 'release', 'upload', "v#{release.version}", '--clobber']
          command.push('--repo', @repository) if @repository
          _output, error, status = Open3.capture3(*command, *paths)
          raise "GitHub asset upload failed: #{error.strip}" unless status.success?
        end
        existing.url
      end

      def create_release(tag, paths, notes)
        arguments = command(tag)
        arguments << '--generate-notes' if notes.nil?
        run_with_notes(arguments, notes, paths)
      end

      def run_with_notes(arguments, notes, paths = [])
        return Open3.capture3(*arguments, *paths) if notes.nil?

        Tempfile.create(['ruby-gem-release-notes-', '.md']) do |file|
          file.write(notes)
          file.close
          Open3.capture3(*arguments, '--notes-file', file.path, *paths)
        end
      end

      def edit_release(release)
        tag = "v#{release.version}"
        arguments = ['gh', 'release', 'edit', tag, '--title', tag, '--draft=false', '--prerelease=false']
        arguments.push('--repo', @repository) if @repository
        _output, error, status = run_with_notes(arguments, release.notes)
        raise "GitHub Release update failed: #{error.strip}" unless status.success?
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
