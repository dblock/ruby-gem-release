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
    ENV.update('GITHUB_ACTIONS' => 'true', 'GITHUB_ENV' => File.join(directory, 'environment'),
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
    [' ', '0', 'user', "123\nother"].each do |owner|
      expect { described_class.new(owner: owner) }.to raise_error(ArgumentError, /account ID/)
    end
    expect(Net::HTTP).not_to have_received(:start)
  end

  it 'omits the owner field for an existing-gem exchange' do
    described_class.new.configure!
    expect(JSON.parse(requests.last.body)).to eq('jwt' => 'test-oidc-token')
    expect(ENV.fetch('GEM_HOST_API_KEY')).to eq('test-api-key')
  end

  it 'exports credentials with an empty owner without creating a credentials file' do
    ENV['HOME'] = File.join(directory, 'home')
    allow(Gem).to receive(:user_home).and_return(Dir.home)
    described_class.new(owner: '').configure!
    expect(JSON.parse(requests.last.body)).to eq('jwt' => 'test-oidc-token')
    expect(ENV.values_at('RUBYGEMS_API_KEY', 'BUNDLE_GEM__PUSH_KEY', 'GEM_HOST_API_KEY')).to eq(['test-api-key'] * 3)
    expect(File).not_to exist(File.join(Dir.home, '.gem', 'credentials'))
  end

  it 'leaves existing local credentials untouched' do
    ENV['HOME'] = File.join(directory, 'home')
    allow(Gem).to receive(:user_home).and_return(Dir.home)
    path = File.join(Dir.home, '.gem', 'credentials')
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, 'existing credentials')
    described_class.new.configure!
    expect(File.read(path)).to eq('existing credentials')
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

  it 'does not export credentials when the exchange is rejected', :aggregate_failures do
    responses[1] = Net::HTTPForbidden.new('1.1', '403', 'Forbidden')
    expect { described_class.new(owner: '123').configure! }.to raise_error(/HTTP 403/)
    expect(File).not_to exist(ENV.fetch('GITHUB_ENV'))
    expect(requests.size).to eq(2)
  end

  it 'exchanges a token supplied by another execution provider without contacting GitHub' do
    values = {}
    provider = RubyGemRelease::ExecutionProvider.new(environment: values)
    allow(provider).to receive(:oidc_token).with(audience: 'rubygems.org').and_return('custom-oidc-token')
    responses.replace([success('rubygems_api_key' => 'custom-api-key')])
    described_class.new(owner: '123', provider: provider).configure!
    expect(requests.size).to eq(1)
    expect(JSON.parse(requests.first.body)).to eq('jwt' => 'custom-oidc-token', 'owner' => '123')
    expect(values).to include('GEM_HOST_API_KEY' => 'custom-api-key')
    expect(File).not_to exist(ENV.fetch('GITHUB_ENV'))
  end
end
