# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/workflow/failure'
require 'tmpdir'

RSpec.describe RubyGemRelease::Workflow::Failure do
  around do |example|
    original = ENV.to_h.slice('RUNNER_TEMP', 'GITHUB_ENV', 'RELEASE_STEPS')
    directory = Dir.mktmpdir
    ENV.update('RUNNER_TEMP' => directory, 'GITHUB_ENV' => File.join(directory, 'environment'))
    File.write(ENV.fetch('GITHUB_ENV'), '')
    example.run
  ensure
    %w[RUNNER_TEMP GITHUB_ENV RELEASE_STEPS].each { |key| ENV.delete(key) }
    ENV.update(original)
    FileUtils.remove_entry(directory)
  end

  it 'prefers the failed step with a captured exception when multiple steps fail' do
    ENV['RELEASE_STEPS'] = JSON.generate(
      'preserve_release_artifacts' => { 'outcome' => 'failure' },
      'publish_release' => { 'outcome' => 'failure' }
    )
    described_class.capture!('publish_release', RuntimeError.new('publication failed'))
    described_class.phase!
    expect(File.read(ENV.fetch('GITHUB_ENV'))).to include("RELEASE_FAILURE_PHASE=publish_release\n")
  end

  it 'uses an unmapped failed step ID without captured exception details' do
    ENV['RELEASE_STEPS'] = JSON.generate(
      'prepare_release' => { 'outcome' => 'success' },
      'custom_validation' => { 'outcome' => 'failure' }
    )
    described_class.phase!
    expect(File.read(ENV.fetch('GITHUB_ENV'))).to include("RELEASE_FAILURE_PHASE=custom_validation\n")
  end

  it 'uses unknown when no step failed' do
    ENV['RELEASE_STEPS'] = JSON.generate('publish_release' => { 'outcome' => 'success' })
    described_class.phase!
    expect(File.read(ENV.fetch('GITHUB_ENV'))).to include("RELEASE_FAILURE_PHASE=unknown\n")
  end

  it 'reconstructs a captured Ruby exception only for its failed phase' do
    original = ArgumentError.new('invalid release')
    original.set_backtrace(['release.rb:12'])
    described_class.capture!('prepare_release', original)
    error = described_class.error_for('prepare_release')
    expect(error).to have_attributes(original_class: 'ArgumentError', message: 'invalid release')
    expect(error.backtrace).to eq(original.backtrace)
    expect(described_class.error_for('publish_release')).to be_nil
  end
end
