# frozen_string_literal: true

require 'bundler/gem_helper'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require_relative 'lib/ruby-gem-release/workflow/ruby_gem'
require_relative 'lib/ruby-gem-release/changelog'

Bundler::GemHelper.install_tasks
RubyGemRelease::Workflow::RubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/ruby-gem-release/version.rb', constant: 'VERSION'),
  changelog: RubyGemRelease::Changelog::Intridea.new
).install_tasks

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

task default: %i[spec rubocop]
