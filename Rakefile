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

RSpec::Core::RakeTask.new(:spec)
RSpec::Core::RakeTask.new('spec:integration') do |task|
  task.pattern = 'spec/integration/**/*_spec.rb'
end
RuboCop::RakeTask.new

task default: %i[spec rubocop]
