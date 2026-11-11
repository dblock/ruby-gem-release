# frozen_string_literal: true

require 'json'
require_relative '../execution_provider'

module RubyGemRelease
  module RSpec
    class Provider < ExecutionProvider
      def export(values)
        super
        path = fetch('RELEASE_TEST_ENVIRONMENT')
        previous = File.file?(path) ? JSON.parse(File.read(path)) : {}
        File.write(path, JSON.generate(previous.merge(values)))
      end

      def failed_steps
        JSON.parse(fetch('RELEASE_TEST_FAILURES', '[]'))
      end
    end
  end
end
