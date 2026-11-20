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
    expect(output.string).to eq("Verified RubyGems Trusted Publishing: repository owner/example; environment release; scopes push_rubygem\n")
  end

  it 'skips the check for destinations without RubyGems authentication' do
    allow(RubyGemRelease::Workflow::RubyGemsCredentials).to receive(:new)
    described_class.new(destination: RubyGemRelease::Destination.new, provider: provider, output: output).check!
    expect(output.string).to eq("Skipped RubyGems Trusted Publishing: the destination does not use RubyGems authentication\n")
    expect(RubyGemRelease::Workflow::RubyGemsCredentials).not_to have_received(:new)
  end

  it 'propagates a failed check' do
    allow(RubyGemRelease::Workflow::RubyGemsCredentials).to receive(:new).and_return(credentials)
    allow(credentials).to receive(:check!).and_raise('Credential request failed (HTTP 404)')
    expect { described_class.new(destination: RubyGemRelease::Destination::RubyGems.new, provider: provider, output: output).check! }
      .to raise_error(/HTTP 404/)
    expect(output.string).to eq('')
  end
end
