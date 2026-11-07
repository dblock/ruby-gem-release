# frozen_string_literal: true

require 'bundler/gem_helper'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require_relative 'lib/ruby-gem-release/tasks'
require_relative 'lib/ruby-gem-release/changelog'
require_relative 'lib/ruby-gem-release/github_release'
require_relative 'lib/ruby-gem-release/package'
require_relative 'lib/ruby-gem-release/git'

Bundler::GemHelper.install_tasks
RubyGemRelease::Tasks.install do |tasks|
  version = RubyGemRelease::Version::RubyConstant.new(path: 'lib/ruby-gem-release/version.rb', constant: 'VERSION')
  changelog = RubyGemRelease::Changelog::Intridea.new
  package = RubyGemRelease::Package.new
  git = RubyGemRelease::Git.new
  github = RubyGemRelease::GitHubRelease.new
  tasks.before_release do |release|
    changelog.release!(release.with_version(version.read))
  end
  tasks.publish do |release|
    git.commit!(release)
    package.build!(release)
    git.tag!(release)
    package.publish!(release)
    git.push!(release)
    github.publish!(release, package: package)
  end
  tasks.after_release do |release|
    changelog.prepare_next!(release.with_next_version(version.increment!))
    git.commit_next!(release)
    git.push!
  end
end

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

task default: %i[spec rubocop]
