# frozen_string_literal: true

require 'json'
require_relative '../release_failure'
require_relative '../execution_provider'

module RubyGemRelease
  module Workflow
    class Failure
      class << self
        def phase!(provider: ExecutionProvider.current)
          failed = provider.failed_steps
          phase = failed.find { |step| error_for(step, provider: provider) } || failed.first || 'unknown'
          provider.export('RELEASE_FAILED_STEP_ID' => phase)
        end

        def capture!(phase, error, provider: ExecutionProvider.current)
          return unless provider.directory

          captured_error = ReleaseFailure::CapturedError.capture(error)
          File.open(failure_file(provider), 'w', 0o600) do |file|
            file.write(JSON.generate('phase' => phase, 'error' => captured_error.to_h))
          end
        rescue StandardError => e
          warn "Unable to capture release error details: #{e.message}"
        end

        def error_for(phase, provider: ExecutionProvider.current)
          return unless provider.directory

          failure = JSON.parse(File.read(failure_file(provider)))
          return unless failure.fetch('phase') == phase

          ReleaseFailure::CapturedError.from_h(failure.fetch('error'))
        rescue Errno::ENOENT
          nil
        end

        private

        def failure_file(provider)
          File.join(provider.directory, 'ruby-gem-release-failure.json')
        end
      end
    end
  end
end
