# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/workflow/ruby_gems_credentials'
require 'tmpdir'

RSpec.describe RubyGemRelease::Workflow::RubyGemsCredentials do
  let(:directory) { Dir.mktmpdir }
  let(:requests) { [] }
  let(:responses) { [success('value' => 'test-oidc-token'), success('rubygems_api_key' => 'test-api-key')] }

  around do |example|
    original = ENV.to_h
    ENV.update('GITHUB_ENV' => File.join(directory, 'environment'),
               'ACTIONS_ID_TOKEN_REQUEST_URL' => 'https://example.com/token?existing=value',
               'ACTIONS_ID_TOKEN_REQUEST_TOKEN' => 'test-request-token')
    example.run
  ensure
    ENV.replace(original)
    FileUtils.remove_entry(directory)
  end

  before do
    allow(Net::HTTP).to receive(:start) do |_host, _port, **_options, &block|
      http = instance_double(Net::HTTP)
      allow(http).to receive(:request) do |request|
        requests << request
        responses.shift
      end
      block.call(http)
    end
  end

  def success(body)
    Net::HTTPOK.new('1.1', '200', 'OK').tap do |result|
      allow(result).to receive(:body).and_return(JSON.generate(body))
    end
  end

  it 'exchanges an owner-bound token and masks credentials before exporting them', :aggregate_failures do
    expect { described_class.new(owner: '123').configure! }
      .to output("::add-mask::test-oidc-token\n::add-mask::test-api-key\n").to_stdout
    expect(requests.first.path).to eq('/token?existing=value&audience=rubygems.org')
    expect(requests.first['Authorization']).to eq('Bearer test-request-token')
    expect(requests.last).to be_a(Net::HTTP::Post)
    expect(requests.last.path).to eq('/api/v1/oidc/trusted_publisher/exchange_token')
    expect(requests.last['Content-Type']).to eq('application/json')
    expect(JSON.parse(requests.last.body)).to eq('jwt' => 'test-oidc-token', 'owner' => '123')
    expect(Net::HTTP).to have_received(:start).with('rubygems.org', 443, use_ssl: true, open_timeout: 10, read_timeout: 30, max_retries: 0)
    expect(File.read(ENV.fetch('GITHUB_ENV'))).to eq("RUBYGEMS_API_KEY=test-api-key\nBUNDLE_GEM__PUSH_KEY=test-api-key\nGEM_HOST_API_KEY=test-api-key\n")
  end

  it 'rejects invalid owners before making credential requests', :aggregate_failures do
    ['', '0', 'user', "123\nother"].each do |owner|
      expect { described_class.new(owner: owner) }.to raise_error(ArgumentError, /account ID/)
    end
    expect(Net::HTTP).not_to have_received(:start)
  end

  it 'replaces the audience without discarding repeated query parameters', :aggregate_failures do
    ENV['ACTIONS_ID_TOKEN_REQUEST_URL'] = 'https://example.com/token?existing=first&audience=old&existing=second'
    expect { described_class.new(owner: '123').configure! }.to output.to_stdout
    expect(requests.first.path).to eq('/token?existing=first&existing=second&audience=rubygems.org')
  end

  it 'does not leak failed response bodies or export credentials', :aggregate_failures do
    failure = Net::HTTPForbidden.new('1.1', '403', 'Forbidden')
    responses[0] = failure
    expect { described_class.new(owner: '123').configure! }.to raise_error(/HTTP 403/)
    expect(File).not_to exist(ENV.fetch('GITHUB_ENV'))
    expect(requests.size).to eq(1)
  end

  it 'does not export a malformed exchange response', :aggregate_failures do
    responses[1] = success('rubygems_api_key' => "invalid\nvalue")
    expect { described_class.new(owner: '123').configure! }.to raise_error(/valid token/)
    expect(File).not_to exist(ENV.fetch('GITHUB_ENV'))
  end

  it 'rejects an insecure token request endpoint before sending authorization' do
    ENV['ACTIONS_ID_TOKEN_REQUEST_URL'] = 'http://example.com/token'
    expect { described_class.new(owner: '123').configure! }.to raise_error(ArgumentError, /HTTPS/)
  end

  it 'does not export credentials when the exchange is rejected', :aggregate_failures do
    responses[1] = Net::HTTPForbidden.new('1.1', '403', 'Forbidden')
    expect { described_class.new(owner: '123').configure! }.to raise_error(/HTTP 403/)
    expect(File).not_to exist(ENV.fetch('GITHUB_ENV'))
    expect(requests.size).to eq(2)
  end

  it 'rejects malformed JSON without exposing response content', :aggregate_failures do
    allow(responses.first).to receive(:body).and_return('invalid-test-secret')
    expect { described_class.new(owner: '123').configure! }.to raise_error('Credential response was not valid JSON')
    expect(File).not_to exist(ENV.fetch('GITHUB_ENV'))
  end
end
