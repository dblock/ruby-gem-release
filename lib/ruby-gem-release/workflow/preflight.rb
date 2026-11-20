# frozen_string_literal: true

require_relative '../execution_provider'
require_relative '../execution_provider/github'
require_relative 'ruby_gems_credentials'
require_relative 'github_permissions'

module RubyGemRelease
  module Workflow
    # Checks release prerequisites without editing files, pushing, or publishing.
    class Preflight
      def initialize(destination:, provider: ExecutionProvider.current, output: $stdout, github: nil)
        @destination = destination
        @provider = provider
        @output = output
        @github = github
      end

      def check!
        @output.puts(trusted_publishing)
        @output.puts(github_permissions)
      end

      private

      def github_permissions
        return 'Skipped GitHub permissions: not running on GitHub Actions' unless @github || @provider.is_a?(ExecutionProvider::GitHub)

        (@github || GitHubPermissions.new(branch: @provider.fetch('DEFAULT_BRANCH', ''), tag: release_tag,
                                          api: GitHubAPI.new(repository: @provider.fetch('GITHUB_REPOSITORY', nil)))).check!
      end

      def release_tag
        version = [@provider.fetch('INPUT_VERSION', ''), @provider.fetch('GEMSPEC_VERSION', '')].find { |value| !value.empty? }
        "v#{version}" if version
      end

      def trusted_publishing
        return 'Skipped RubyGems Trusted Publishing: the destination does not use RubyGems authentication' unless @destination.authentication == 'rubygems'

        summary = RubyGemsCredentials.new(owner: @provider.fetch('RUBYGEMS_OWNER_ID', ''), provider: @provider).check!
        details = summary.except('scopes').map { |name, value| "#{name} #{value}" }
        "Verified RubyGems Trusted Publishing: #{[*details, "scopes #{summary.fetch('scopes').join(', ')}"].join('; ')}"
      end
    end
  end
end
