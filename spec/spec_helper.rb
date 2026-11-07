# frozen_string_literal: true

require 'bundler/setup'
require 'simplecov'
require 'simplecov-lcov'

SimpleCov::Formatter::LcovFormatter.config.report_with_single_file = true
SimpleCov::Formatter::LcovFormatter.config.single_report_path = 'coverage/lcov.info'
coverage_formatters = [
  SimpleCov::Formatter::HTMLFormatter,
  SimpleCov::Formatter::LcovFormatter
]
SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter.new(coverage_formatters)
SimpleCov.start do
  skip '/spec/'
  skip 'lib/ruby-gem-release/version.rb'
  cover 'lib/**/*.rb'
end

require 'ruby-gem-release'
require 'rspec'

RSpec.configure do |config|
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
