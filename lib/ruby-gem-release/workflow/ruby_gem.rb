# frozen_string_literal: true

require_relative '../tasks'
require_relative '../package/ruby_gem'
require_relative '../source_control/git'
require_relative '../hosting/github_release'

module RubyGemRelease
  module Workflow
    class RubyGem
      def initialize(version:, changelog:, package: Package::RubyGem.new, git: SourceControl::Git.new, hosting: Hosting::GitHubRelease.new)
        @version = version
        @changelog = changelog
        @package = package
        @git = git
        @hosting = hosting
      end

      def install_tasks
        Tasks.install do |tasks|
          tasks.before_release { |release| prepare_release(release) }
          tasks.publish { |release| publish(release) }
          tasks.after_release { |release| prepare_next(release) }
        end
      end

      private

      def prepare_release(release)
        @git.stage_changes! do
          select_version!(release.version) unless ENV.fetch('INPUT_VERSION', '').empty?
          @changelog&.release!(release.with_version(@version.read))
        end
      end

      def select_version!(version)
        raise ArgumentError, 'version object must implement set! when selecting a release version' unless @version.respond_to?(:set!)

        @version.set!(version)
      end

      def publish(release)
        @package.check_version!(release.version)
        @git.commit!(release)
        @package.build!(release)
        @git.tag!(release)
        @package.publish!(release)
        @git.push!(release)
        @hosting&.publish!(release, package: @package)
      end

      def prepare_next(release)
        next_release = nil
        @git.stage_changes! do
          next_release = release.with_next_version(@version.increment!)
          @changelog&.prepare_next!(next_release)
        end
        @git.commit_next!(next_release)
        @git.push!
      end
    end
  end
end
