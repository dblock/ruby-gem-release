# frozen_string_literal: true

require 'bundler/gem_helper'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require_relative 'lib/ruby-gem-release/tasks'

Bundler::GemHelper.install_tasks
RubyGemRelease::Tasks.install(version_file: 'lib/ruby-gem-release/version.rb', version_constant: 'VERSION')

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

task default: %i[spec rubocop]
