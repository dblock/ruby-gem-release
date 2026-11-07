# frozen_string_literal: true

require 'bundler/gem_helper'
require 'rspec/core/rake_task'
require 'rubocop/rake_task'
require_relative 'lib/ruby-gem-release/tasks'

Bundler::GemHelper.install_tasks
RubyGemRelease::Tasks.install(version_file: 'lib/ruby-gem-release/version.rb', version_constant: 'VERSION') do |release|
  release.before_release do |version:, date:|
    content = File.read('CHANGELOG.md')
    pattern = /^## \d+\.\d+\.\d+ \(Next\)$/
    matches = content.to_enum(:scan, pattern).map { Regexp.last_match }
    raise 'Expected exactly one unreleased changelog heading' unless matches.one?

    match = matches.first
    section_end = content.index(/^## /, match.end(0)) || content.length
    section = content[match.end(0)...section_end]
    placeholder = /^- Your contribution here\.\r?\n/
    raise 'Expected exactly one contribution placeholder' unless section.scan(placeholder).one?

    heading = "## #{version} (#{date.strftime('%Y/%m/%d')})"
    File.write('CHANGELOG.md', content[0...match.begin(0)] + heading + section.sub(placeholder, '') + content[section_end..])
  end

  release.after_bump do |version:, released_version:|
    content = File.read('CHANGELOG.md')
    pattern = %r{^## #{Regexp.escape(released_version)} \(\d{4}/\d{2}/\d{2}\)$}
    matches = content.to_enum(:scan, pattern).map { Regexp.last_match }
    raise 'Expected exactly one released changelog heading' unless matches.one?
    raise 'Unreleased changelog heading already exists' if content.match?(/^## \d+\.\d+\.\d+ \(Next\)$/)

    section = "## #{version} (Next)\n\n- Your contribution here.\n\n"
    File.write('CHANGELOG.md', content.insert(matches.first.begin(0), section))
  end
end

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

task default: %i[spec rubocop]
