# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/execution_provider'

RSpec.describe RubyGemRelease::ExecutionProvider do
  it 'selects Actions only when running on Actions' do
    expect(described_class.current(environment: {})).to be_an_instance_of(described_class)
    expect(described_class.current(environment: { 'GITHUB_ACTIONS' => 'false' })).to be_an_instance_of(described_class)
    expect(described_class.current(environment: { 'GITHUB_ACTIONS' => 'true' })).to be_an_instance_of(described_class::GitHub)
  end

  it 'keeps environment and output transport independent of GitHub metadata' do
    values = { 'GITHUB_ENV' => 'missing/path', 'GITHUB_OUTPUT' => 'missing/path', 'RELEASE_STEPS' => 'not JSON' }
    provider = described_class.new(environment: values)
    provider.export('RELEASE_VERSION' => '1.2.3')
    provider.output('proceed' => 'false')
    ctx = provider.context(release: nil, task: 'release:validate', state: nil)
    expect(values.fetch('RELEASE_VERSION')).to eq('1.2.3')
    expect(provider.outputs).to eq('proceed' => 'false')
    expect(ctx).to have_attributes(step: have_attributes(id: 'release:validate'), steps: {}, run: nil)
  end

  it 'rejects line breaks without partially exporting values or outputs' do
    values = {}
    provider = described_class.new(environment: values)
    invalid = { 'FIRST' => 'valid', 'SECOND' => "invalid\nINJECTED=value" }
    expect { provider.export(invalid) }.to raise_error(ArgumentError, /line breaks/)
    expect { provider.output(invalid) }.to raise_error(ArgumentError, /line breaks/)
    expect { provider.export("INVALID\nNAME" => 'value') }.to raise_error(ArgumentError, /identifiers/)
    expect { provider.output('INVALID=value' => 'value') }.to raise_error(ArgumentError, /identifiers/)
    expect(values).to eq({})
    expect(provider.outputs).to eq({})
  end

  it 'requires providers to supply identity tokens explicitly' do
    expect { described_class.new.oidc_token(audience: 'registry.example') }.to raise_error(NotImplementedError, /does not support OIDC/)
  end
end
