# frozen_string_literal: true

require_relative '../execution_provider'
require_relative 'ruby_gems_credentials'

module RubyGemRelease
  module Workflow
    # Checks release prerequisites without editing files, pushing, or publishing.
    class Preflight
      def initialize(destination:, provider: ExecutionProvider.current, output: $stdout)
        @destination = destination
        @provider = provider
        @output = output
      end

      def check!
        @output.puts(trusted_publishing)
      end

      private

      def trusted_publishing
        return 'Skipped RubyGems Trusted Publishing: the destination does not use RubyGems authentication' unless @destination.authentication == 'rubygems'

        summary = RubyGemsCredentials.new(owner: @provider.fetch('RUBYGEMS_OWNER_ID', ''), provider: @provider).check!
        details = summary.except('scopes').map { |name, value| "#{name} #{value}" }
        "Verified RubyGems Trusted Publishing: #{[*details, "scopes #{summary.fetch('scopes').join(', ')}"].join('; ')}"
      end
    end
  end
end
