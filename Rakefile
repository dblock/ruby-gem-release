# frozen_string_literal: true

require 'bundler/gem_helper'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require_relative 'lib/ruby-gem-release/workflow/ruby_gem'
require_relative 'lib/ruby-gem-release/changelog'
require_relative 'tasks/release_version'

Bundler::GemHelper.install_tasks
RubyGemRelease::Workflow::RubyGem.new(
  version: ReleaseVersion.new(path: 'lib/ruby-gem-release/version.rb', constant: 'VERSION', readme_path: 'README.md'),
  changelog: RubyGemRelease::Changelog::Intridea.new
).install_tasks

{
  spec: 'spec/**/*_spec.rb',
  'spec:integration' => 'spec/integration/**/*_spec.rb'
}.each do |name, pattern|
  desc "Run #{name} in parallel"
  task name do
    FileUtils.rm_f('coverage/.resultset.json')
    files = Dir.glob(ENV.fetch('SPEC', pattern))
    abort "No spec files match #{ENV.fetch('SPEC', pattern).inspect}" if files.empty?

    sh 'bundle', 'exec', 'parallel_rspec', '--serialize-stdout', '--test-options', ENV.fetch('SPEC_OPTS', ''), *files
  ensure
    require_relative 'spec/coverage_setup'
    SimpleCov.collate(['coverage/.resultset.json']) if File.file?('coverage/.resultset.json')
  end
end
RSpec::Core::RakeTask.new('spec:serial')
RSpec::Core::RakeTask.new('spec:unit') do |task|
  task.exclude_pattern = 'spec/integration/**/*_spec.rb'
end
RuboCop::RakeTask.new

task default: %i[spec rubocop]
