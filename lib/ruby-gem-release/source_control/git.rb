# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'
require_relative 'git/preparation'

module RubyGemRelease
  module SourceControl
    class Git
      def initialize(branch: nil, remote: 'origin', directory: nil)
        @remote = remote
        @branch = branch || ENV.fetch('DEFAULT_BRANCH', nil)
        directory ||= ENV.fetch('RELEASE_DIRECTORY', nil)
        @directory = directory.to_s.empty? ? Dir.mktmpdir('ruby-gem-release-git-') : directory
      end

      def configure!(name: 'ruby-gem-release', email: 'ruby-gem-release@localhost')
        [name, email].each do |value|
          raise ArgumentError, 'Git identity must be nonempty and contain no line breaks' unless value.is_a?(String) && !value.strip.empty? && !value.match?(/[\r\n]/)
        end
        run('config', '--local', 'user.name', name)
        run('config', '--local', 'user.email', email)
      end

      def head
        run('rev-parse', 'HEAD').strip
      end

      def check_tag!(version)
        output, _error, status = Open3.capture3('git', 'show-ref', '--verify', '--quiet', "refs/tags/v#{version}")
        raise "Release tag already exists: v#{version}" if status.success?
        raise "Cannot check release tag: #{output}" unless status.exitstatus == 1
      end

      def check_current!(_release, expected: head)
        run('fetch', @remote, branch, '--tags')
        raise 'Default branch advanced; start a new release' unless remote_head == expected
      end

      def check_clean!
        preparation.check_clean!
      end

      def stage_changes!(&)
        preparation.stage_changes!(&)
      end

      def commit!(release)
        @release = release
        @initial_commit = ENV['RELEASE_INITIAL_COMMIT'] || head
        commit_changes("Prepare release #{release.version}", required: false)
      end

      def commit_next!(release)
        raise ArgumentError, 'next development iteration version is required' if release.next_version.to_s.empty?

        @release = release
        @next_commit_parent = head
        commit_changes("Prepare next development iteration, #{release.next_version}", required: true)
      end

      def tag!(release)
        @release = release
        ensure_clean!
        check_current!(release, expected: @initial_commit || ENV.fetch('RELEASE_INITIAL_COMMIT'))
        check_tag!(release.version)
        run('tag', "v#{release.version}")
        FileUtils.mkdir_p(@directory)
        run('bundle', 'create', File.join(@directory, 'release.bundle'), 'HEAD', "refs/tags/v#{release.version}")
      end

      def push!(release = @release)
        raise ArgumentError, 'a release context is required before pushing' unless release

        if @next_commit_parent
          check_current!(release, expected: @next_commit_parent)
          run('push', @remote, "HEAD:refs/heads/#{branch}")
        else
          check_current!(release, expected: @initial_commit || ENV.fetch('RELEASE_INITIAL_COMMIT'))
          run('push', '--atomic', @remote, "HEAD:refs/heads/#{branch}", "refs/tags/v#{release.version}")
        end
      end

      private

      def branch
        @branch ||= run('symbolic-ref', "refs/remotes/#{@remote}/HEAD").strip.delete_prefix("refs/remotes/#{@remote}/")
      end

      def remote_head
        run('rev-parse', "refs/remotes/#{@remote}/#{branch}").strip
      end

      def ensure_clean!
        raise 'Gem build changed the working tree after the release commit' unless run('status', '--porcelain', '--untracked-files=all').empty?
      end

      def commit_changes(message, required:)
        preparation.verify!
        output = run('diff', '--cached', '--name-only', '-z')
        raise 'Preparing the next development iteration did not change any files' if required && output.empty?

        if output.empty?
          preparation.clear!
          return head
        end

        run('commit', '-m', message)
        preparation.clear!
        head
      end

      def preparation
        @preparation ||= Preparation.new(directory: @directory, &method(:run))
      end

      def run(*)
        output, error, status = Open3.capture3('git', *)
        raise "Git command failed: #{error.strip}\n#{output.strip}" unless status.success?

        output
      end
    end
  end
end
