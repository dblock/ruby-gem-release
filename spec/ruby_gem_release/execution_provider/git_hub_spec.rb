# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/execution_provider/github'
require 'tmpdir'

RSpec.describe RubyGemRelease::ExecutionProvider::GitHub do
  subject(:provider) { described_class.new(environment: environment) }

  let(:directory) { Dir.mktmpdir }
  let(:environment) { { 'GITHUB_ENV' => File.join(directory, 'environment'), 'GITHUB_OUTPUT' => File.join(directory, 'output') } }

  after { FileUtils.remove_entry(directory) }

  it 'exports values to subsequent steps and the current process environment' do
    provider.export('RELEASE_VERSION' => '1.2.3')
    expect(File.read(environment.fetch('GITHUB_ENV'))).to eq("RELEASE_VERSION=1.2.3\n")
    expect(File).not_to exist(environment.fetch('GITHUB_OUTPUT'))
    expect(environment.fetch('RELEASE_VERSION')).to eq('1.2.3')
  end

  it 'uses original failures rather than conclusions when selecting failed steps' do
    environment['RELEASE_STEPS_JSON'] = JSON.generate(
      'continued' => { 'outcome' => 'failure', 'conclusion' => 'success' },
      'skipped' => { 'outcome' => 'skipped', 'conclusion' => 'skipped' }
    )
    expect(provider.failed_steps).to eq(['continued'])
  end

  context 'when requesting identity tokens' do
    let(:requests) { [] }
    let(:response) { Net::HTTPOK.new('1.1', '200', 'OK') }

    before do
      environment.update('ACTIONS_ID_TOKEN_REQUEST_URL' => 'https://example.com/token?existing=value', 'ACTIONS_ID_TOKEN_REQUEST_TOKEN' => 'test-request-token')
      allow(response).to receive(:body).and_return(JSON.generate('value' => 'test-oidc-token'))
      allow(Net::HTTP).to receive(:start) do |_host, _port, **_options, &block|
        http = instance_double(Net::HTTP)
        allow(http).to receive(:request) do |request|
          requests << request
          response
        end
        block.call(http)
      end
    end

    it 'requests the supplied audience without embedding a registry choice' do
      expect(provider.oidc_token(audience: 'registry.example')).to eq('test-oidc-token')
      expect(requests.first.path).to eq('/token?existing=value&audience=registry.example')
      expect(requests.first['Authorization']).to eq('Bearer test-request-token')
      expect(Net::HTTP).to have_received(:start).with('example.com', 443, use_ssl: true, open_timeout: 10, read_timeout: 30, max_retries: 0)
    end

    it 'replaces the audience without discarding repeated query parameters' do
      environment['ACTIONS_ID_TOKEN_REQUEST_URL'] = 'https://example.com/token?existing=first&audience=old&existing=second'
      provider.oidc_token(audience: 'registry.example')
      expect(requests.first.path).to eq('/token?existing=first&existing=second&audience=registry.example')
    end

    it 'rejects insecure endpoints before sending authorization' do
      environment['ACTIONS_ID_TOKEN_REQUEST_URL'] = 'http://example.com/token'
      expect { provider.oidc_token(audience: 'registry.example') }.to raise_error(ArgumentError, /HTTPS/)
      expect(Net::HTTP).not_to have_received(:start)
    end

    it 'rejects malformed JSON without exposing response content' do
      allow(response).to receive(:body).and_return('invalid-test-secret')
      expect { provider.oidc_token(audience: 'registry.example') }.to raise_error('OIDC response was not valid JSON')
    end

    it 'rejects missing and malformed tokens' do
      [[], {}, { 'value' => '' }, { 'value' => "invalid\nvalue" }].each do |body|
        allow(response).to receive(:body).and_return(JSON.generate(body))
        expect { provider.oidc_token(audience: 'registry.example') }.to raise_error(/valid token/)
      end
    end
  end
end
