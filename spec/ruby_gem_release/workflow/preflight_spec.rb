# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'ruby-gem-release/workflow/preflight'
require 'ruby-gem-release/destination/ruby_gems'

RSpec.describe RubyGemRelease::Workflow::Preflight do
  let(:output) { StringIO.new }
  let(:provider) { RubyGemRelease::ExecutionProvider.new(environment: { 'RUBYGEMS_OWNER_ID' => '123' }) }
  let(:credentials) { instance_double(RubyGemRelease::Workflow::RubyGemsCredentials) }

  it 'verifies RubyGems Trusted Publishing with the configured owner and reports what matched' do
    allow(RubyGemRelease::Workflow::RubyGemsCredentials).to receive(:new).with(owner: '123', provider: provider).and_return(credentials)
    allow(credentials).to receive(:check!).and_return('repository' => 'owner/example', 'environment' => 'release', 'scopes' => ['push_rubygem'])
    described_class.new(destination: RubyGemRelease::Destination::RubyGems.new, provider: provider, output: output).check!
    expect(output.string).to eq("Verified RubyGems Trusted Publishing: repository owner/example; environment release; scopes push_rubygem\n" \
                                "Skipped GitHub permissions: not running on GitHub Actions\n")
  end

  it 'skips the check for destinations without RubyGems authentication' do
    allow(RubyGemRelease::Workflow::RubyGemsCredentials).to receive(:new)
    described_class.new(destination: RubyGemRelease::Destination.new, provider: provider, output: output).check!
    expect(output.string).to eq("Skipped RubyGems Trusted Publishing: the destination does not use RubyGems authentication\n" \
                                "Skipped GitHub permissions: not running on GitHub Actions\n")
    expect(RubyGemRelease::Workflow::RubyGemsCredentials).not_to have_received(:new)
  end

  it 'propagates a failed check' do
    allow(RubyGemRelease::Workflow::RubyGemsCredentials).to receive(:new).and_return(credentials)
    allow(credentials).to receive(:check!).and_raise('Credential request failed (HTTP 404)')
    expect { described_class.new(destination: RubyGemRelease::Destination::RubyGems.new, provider: provider, output: output).check! }
      .to raise_error(/HTTP 404/)
    expect(output.string).to eq('')
  end

  context 'with GitHub Actions' do
    let(:environment) { { 'GITHUB_ACTIONS' => 'true', 'DEFAULT_BRANCH' => 'main', 'GITHUB_REPOSITORY' => 'owner/example', 'GEMSPEC_VERSION' => '1.2.3', 'INPUT_VERSION' => '' } }
    let(:provider) { RubyGemRelease::ExecutionProvider::GitHub.new(environment: environment) }
    let(:permissions) { instance_double(RubyGemRelease::Workflow::GitHubPermissions, check!: ['Verified GitHub push access to main and tag v1.2.3']) }

    before { allow(RubyGemRelease::Workflow::GitHubPermissions).to receive(:new).and_return(permissions) }

    it 'checks the default branch and the captured release tag' do
      described_class.new(destination: RubyGemRelease::Destination.new, provider: provider, output: output).check!
      expect(RubyGemRelease::Workflow::GitHubPermissions).to have_received(:new).with(branch: 'main', tag: 'v1.2.3', api: an_instance_of(RubyGemRelease::GitHubAPI))
      expect(output.string.lines.last).to eq("Verified GitHub push access to main and tag v1.2.3\n")
    end

    it 'checks the selected release version tag and omits the tag when no version is known' do
      environment['INPUT_VERSION'] = '2.0.0'
      described_class.new(destination: RubyGemRelease::Destination.new, provider: provider, output: output).check!
      environment.merge!('INPUT_VERSION' => '', 'GEMSPEC_VERSION' => '')
      described_class.new(destination: RubyGemRelease::Destination.new, provider: provider, output: output).check!
      expect(RubyGemRelease::Workflow::GitHubPermissions).to have_received(:new).with(hash_including(tag: 'v2.0.0')).ordered
      expect(RubyGemRelease::Workflow::GitHubPermissions).to have_received(:new).with(hash_including(tag: nil)).ordered
    end
  end
end
