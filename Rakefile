# frozen_string_literal: true

require 'bundler/gem_helper'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require_relative 'lib/ruby-gem-release/tasks'
require_relative 'lib/ruby-gem-release/changelog'
require_relative 'lib/ruby-gem-release/github_release'
require 'fileutils'

Bundler::GemHelper.install_tasks
RubyGemRelease::Tasks.install do |tasks|
  version = RubyGemRelease::Version::RubyConstant.new(path: 'lib/ruby-gem-release/version.rb', constant: 'VERSION')
  changelog = RubyGemRelease::Changelog::Intridea.new
  tasks.before_release do |release|
    changelog.release!(release.with_version(version.read))
  end
  tasks.publish do |release|
    directory = ENV.fetch('RUNNER_TEMP')
    artifact = File.join(directory, "#{ENV.fetch('GEM_NAME')}-#{release.version}.gem")
    FileUtils.cp(File.join(directory, 'release.gem'), artifact)
    github_release = RubyGemRelease::GitHubRelease.new(repository: ENV.fetch('GITHUB_REPOSITORY'))
    puts github_release.publish!(release, artifacts: [artifact])
  end
  tasks.after_release do |release|
    changelog.prepare_next!(release.with_next_version(version.increment!))
  end
end

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

task default: %i[spec rubocop]
