# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)
require 'ruby-gem-release/version'

Gem::Specification.new do |s|
  s.name        = 'ruby-gem-release'
  s.version     = RubyGemRelease::VERSION
  s.authors     = ['Daniel Doubrovkine']
  s.email       = ['dblock@users.noreply.github.com']
  s.homepage    = 'https://github.com/dblock/ruby-gem-release'
  s.summary     = 'Reusable release workflow and Rake tasks for Ruby gems.'
  s.description = 'Reusable GitHub Actions workflow and Rake tasks for Ruby gem releases.'
  s.license     = 'MIT'
  s.required_ruby_version = '>= 3.3'

  s.files         = %w[CHANGELOG.md LICENSE.txt README.md] + Dir['lib/**/*.rb', 'tasks/**/*.rake']
  s.require_paths = ['lib']
  s.metadata = {
    'bug_tracker_uri' => 'https://github.com/dblock/ruby-gem-release/issues',
    'changelog_uri' => 'https://github.com/dblock/ruby-gem-release/blob/master/CHANGELOG.md',
    'rubygems_mfa_required' => 'true',
    'source_code_uri' => 'https://github.com/dblock/ruby-gem-release'
  }

  s.add_dependency 'rake', '>= 13'
end
