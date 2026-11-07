# frozen_string_literal: true

require_relative 'version'

Gem::Specification.new do |spec|
  spec.name = 'ruby-gem-release-test-fixture'
  spec.version = ReleaseConsumer::VERSION
  spec.authors = ['Fixture']
  spec.summary = 'A release workflow integration fixture'
  spec.files = ['spec/fixtures/release_consumer/version.rb']
  spec.metadata['rubygems_mfa_required'] = 'true'
end
