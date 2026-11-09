# frozen_string_literal: true

require 'json'
require_relative '../release_failure'

module RubyGemRelease
  module Workflow
    class Failure
      class << self
        def phase!
          steps = JSON.parse(ENV.fetch('RELEASE_STEPS'))
          failed = steps.select { |_, step| step['outcome'] == 'failure' }.keys
          phase = failed.find { |step| error_for(step) } || failed.first || 'unknown'
          File.open(ENV.fetch('GITHUB_ENV'), 'a') { |file| file.puts "RELEASE_FAILURE_PHASE=#{phase}" }
        end

        def capture!(phase, error)
          return if ENV.fetch('RUNNER_TEMP', '').empty?

          captured_error = ReleaseFailure::CapturedError.capture(error)
          File.open(failure_file, 'w', 0o600) do |file|
            file.write(JSON.generate('phase' => phase, 'error' => captured_error.to_h))
          end
        rescue StandardError => e
          warn "Unable to capture release error details: #{e.message}"
        end

        def error_for(phase)
          return if ENV.fetch('RUNNER_TEMP', '').empty?

          failure = JSON.parse(File.read(failure_file))
          return unless failure.fetch('phase') == phase

          ReleaseFailure::CapturedError.from_h(failure.fetch('error'))
        rescue Errno::ENOENT
          nil
        end

        private

        def failure_file
          File.join(ENV.fetch('RUNNER_TEMP'), 'ruby-gem-release-failure.json')
        end
      end
    end
  end
end
