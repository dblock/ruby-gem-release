# frozen_string_literal: true

require 'bundler/gem_helper'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require_relative 'lib/ruby-gem-release/tasks'
require_relative 'lib/ruby-gem-release/changelog'

Bundler::GemHelper.install_tasks
RubyGemRelease::Tasks.install do |tasks|
  version = RubyGemRelease::Version::RubyConstant.new(path: 'lib/ruby-gem-release/version.rb', constant: 'VERSION')
  changelog = RubyGemRelease::Changelog::Intridea.new
  tasks.before_release do |release|
    changelog.release!(release.with_version(version.read))
  end
  tasks.after_release do |release|
    changelog.prepare_next!(release.with_next_version(version.increment!))
  end
end

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

task default: %i[spec rubocop]
