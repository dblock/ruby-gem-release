# frozen_string_literal: true

require 'bundler/setup'
require_relative 'coverage_setup'

SimpleCov.command_name("RSpec#{ENV.fetch('TEST_ENV_NUMBER', '')}")
SimpleCov.merging(ENV.key?('TEST_ENV_NUMBER'))
SimpleCov.start do
  skip '/spec/'
  skip 'lib/ruby-gem-release/version.rb'
  cover 'lib/**/*.rb'
end
# The Rake task formats coverage after all workers have stored their results.
SimpleCov.at_exit { SimpleCov.result } if ENV.key?('TEST_ENV_NUMBER')

require 'ruby-gem-release'
require 'rspec'

RSpec.configure do |config|
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
