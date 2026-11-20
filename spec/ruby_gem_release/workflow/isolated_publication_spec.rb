# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'ruby-gem-release/workflow/semantic_ruby_gem'

RSpec.describe RubyGemRelease::Workflow::IsolatedPublication do
  let(:directory) { Dir.mktmpdir }
  let(:components) do
    { package: RubyGemRelease::Package::RubyGem.allocate, destination: RubyGemRelease::Destination::RubyGems.new,
      git: RubyGemRelease::SourceControl::Git.new(directory: directory), hosting: RubyGemRelease::Hosting::GitHubRelease.new(repository: nil) }
  end
  let(:hooks) { [] }
  let(:provider) { RubyGemRelease::ExecutionProvider.new(environment: { 'GITHUB_REPOSITORY' => 'owner/project' }) }
  let(:workflow) do
    Struct.new(:package, :destination, :git, :hosting, :registered, :provider) do
      def hooks?(stage) = registered.include?(stage)
    end.new(*components.values_at(:package, :destination, :git, :hosting), hooks, provider)
  end

  # Actions sets GITHUB_REPOSITORY, which the default hosting also reads.
  around do |example|
    original = ENV.fetch('GITHUB_REPOSITORY', nil)
    ENV['GITHUB_REPOSITORY'] = 'owner/project'
    example.run
  ensure
    original ? ENV['GITHUB_REPOSITORY'] = original : ENV.delete('GITHUB_REPOSITORY')
    FileUtils.rm_rf(directory)
  end

  it 'accepts the default components, disabled hosting, and build-stage hooks' do
    hooks.push(:prepare_release, :prepare_next, :commit_next)
    expect { described_class.check!(workflow, callbacks: false) }.not_to raise_error
    workflow.hosting = nil
    expect { described_class.check!(workflow, callbacks: false) }.not_to raise_error
  end

  it 'rejects components the publish job cannot reproduce', :aggregate_failures do
    { package: Object.new, destination: Class.new(RubyGemRelease::Destination::RubyGems).new, git: Object.new }.each do |name, replacement|
      original = workflow[name]
      workflow[name] = replacement
      expect { described_class.check!(workflow, callbacks: false) }.to raise_error(ArgumentError, "isolated publication requires the default #{name}")
      workflow[name] = original
    end
    workflow.hosting = RubyGemRelease::Hosting::GitHubRelease.new(repository: 'owner/project')
    expect { described_class.check!(workflow, callbacks: false) }.not_to raise_error
    workflow.hosting = RubyGemRelease::Hosting::GitHubRelease.new(repository: 'other/repository')
    expect { described_class.check!(workflow, callbacks: false) }.to raise_error(ArgumentError, /default GitHub Release hosting/)
  end

  it 'rejects project callbacks and publication-stage hooks', :aggregate_failures do
    expect { described_class.check!(workflow, callbacks: true) }.to raise_error(ArgumentError, /no project success or failure callbacks/)
    hooks.push(:push_release, :success)
    expect { described_class.check!(workflow, callbacks: false) }.to raise_error(ArgumentError, 'isolated publication runs no project hooks for push_release, success')
  end

  it 'refuses an unsupported handoff format before any Git or registry operation' do
    File.write(File.join(directory, described_class::FILE), JSON.generate('format' => 2))
    provider = RubyGemRelease::ExecutionProvider.new(environment: { 'RELEASE_DATA_DIR' => directory })
    destination = instance_double(RubyGemRelease::Destination::RubyGems)
    expect { described_class.new(provider: provider, destination: destination).publish! }.to raise_error(ArgumentError, /unsupported isolated publication format/)
  end

  it 'seals semantic releases without a development iteration unless bumping is enabled' do
    allow(described_class).to receive(:check!)
    allow(described_class).to receive(:seal!) { |release:, **| release }
    values = { 'INPUT_VERSION' => '', 'SOURCE_COMMIT' => 'a' * 40, 'GEMSPEC_VERSION' => '1.2.3', 'RELEASE_VERSION' => '1.3.0', 'RELEASE_DATE' => '2026-11-20' }
    provider = RubyGemRelease::ExecutionProvider.new(environment: values)
    decision = RubyGemRelease::SemanticRelease::Decision.new(head: 'a' * 40, last_release: nil, commits: [], release_type: 'minor', version: '1.3.0', notes: 'Notes.')
    version = instance_double(RubyGemRelease::Version::RubyConstant, read: '1.3.0', set!: nil, increment!: '1.3.1')
    workflow = RubyGemRelease::Workflow::SemanticRubyGem.new(version: version, provider: provider, **components.slice(:package, :destination, :git))
    state = RubyGemRelease::Workflow::State.new
    state.record_analysis!(decision)
    release = RubyGemRelease::Release.new(version: '1.3.0', gemspec_version: '1.2.3', date: Date.new(2026, 11, 20), notes: 'Notes.')
    sealed = workflow.seal!(provider.context(release: release, task: 'release:workflow:seal', state: state, workflow: workflow, analysis: decision))
    expect(sealed).to have_attributes(version: '1.3.0', next_version: nil, notes: 'Notes.')
    expect(version).not_to have_received(:increment!)
  end
end
