# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/workflow/environment'
require 'tmpdir'

RSpec.describe RubyGemRelease::Workflow::Environment do
  let(:directory) { Dir.mktmpdir }
  let(:environment_file) { File.join(directory, 'environment') }
  let(:git) { instance_double(RubyGemRelease::SourceControl::Git, configure!: nil, check_clean!: nil, check_current!: nil, check_tag!: nil, stage_changes!: nil, head: 'initial-commit') }

  around do |example|
    original = ENV.to_h
    ENV.update('GITHUB_ACTIONS' => 'true', 'GITHUB_ENV' => environment_file, 'INPUT_VERSION' => '', 'GITHUB_REF' => 'refs/heads/master', 'DEFAULT_BRANCH' => 'master', 'RUNNER_TEMP' => directory)
    ENV.delete('GEMSPEC')
    ENV.delete('INPUT_GEMSPEC')
    ENV.delete('TZ')
    Dir.chdir(directory) { example.run }
  ensure
    ENV.replace(original)
    FileUtils.remove_entry(directory)
  end

  before do
    File.write('fixture.gemspec', "require_relative 'version'\nGem::Specification.new { |spec| spec.name = 'fixture'; spec.version = VERSION }\n")
    File.write('version.rb', "VERSION = '1.2.3'\n")
    File.write(environment_file, '')
    allow(RubyGemRelease::SourceControl::Git).to receive(:new).and_return(git)
    http = instance_double(Net::HTTP)
    response = instance_double(Net::HTTPResponse, code: '404')
    allow(Net::HTTP).to receive(:start).with('rubygems.org', 443, use_ssl: true, open_timeout: 10, read_timeout: 30, max_retries: 0).and_yield(http)
    allow(http).to receive(:get).and_return(response)
  end

  it 'retains the initial version while resolving callback edits', :aggregate_failures do
    described_class.new.capture!
    File.write('version.rb', "VERSION = '2.0.0'\n")
    described_class.new.resolve!
    expect(File.read(environment_file)).to include("RELEASE_PREVIOUS_VERSION=1.2.3\n", "RELEASE_VERSION=2.0.0\n", "RELEASE_INITIAL_COMMIT=initial-commit\n")
  end

  it 'exports independent private state files for successive captures' do
    described_class.new.capture!
    first = File.readlines(environment_file, chomp: true).grep(/\ARELEASE_STATE=/).last.delete_prefix('RELEASE_STATE=')
    RubyGemRelease::Workflow::State.new(path: first).record_next_version!('1.2.4')
    described_class.new.capture!
    second = File.readlines(environment_file, chomp: true).grep(/\ARELEASE_STATE=/).last.delete_prefix('RELEASE_STATE=')
    expect(first).not_to eq(second)
    expect(RubyGemRelease::Workflow::State.new(path: second).next_version).to be_nil
  end

  it 'defaults the calendar date to UTC rather than the server timezone' do
    allow(Time).to receive(:now).and_return(Time.new(2026, 11, 7, 23, 30, 0, '-05:00'))
    described_class.new.capture!
    expect(File.read(environment_file)).to include("RELEASE_DATE=2026-11-08\n")
  end

  it 'retains the captured calendar date when a later phase crosses midnight' do
    ENV['TZ'] = 'America/New_York'
    allow(Time).to receive(:now).and_return(Time.utc(2026, 11, 8, 4, 30))
    described_class.new.capture!
    allow(Time).to receive(:now).and_return(Time.utc(2026, 11, 8, 5, 30))
    described_class.new.resolve!
    expect(File.readlines(environment_file).grep(/\ARELEASE_DATE=/)).to eq(["RELEASE_DATE=2026-11-07\n"])
  end

  it 'uses the configured timezone across midnight and daylight saving changes', :aggregate_failures do
    ENV['TZ'] = 'America/New_York'
    [[Time.utc(2026, 11, 8, 4, 30), '2026-11-07'], [Time.utc(2026, 7, 8, 4, 30), '2026-07-08']].each do |instant, date|
      File.write(environment_file, '')
      allow(Time).to receive(:now).and_return(instant)
      described_class.new.capture!
      expect(File.read(environment_file)).to include("RELEASE_DATE=#{date}\n")
    end
  end

  it 'rejects unknown timezones and traversal before configuring Git or exporting context', :aggregate_failures do
    ['Unknown/Zone', '../UTC', '', '-05:00'].each do |timezone|
      ENV['TZ'] = timezone
      expect { described_class.new.capture! }.to raise_error(ArgumentError, /timezone/)
    end
    expect(git).not_to have_received(:configure!)
    expect(File.read(environment_file)).to eq('')
  end

  it 'rejects a prepared version that does not honor the selected version', :aggregate_failures do
    ENV['INPUT_VERSION'] = '2.0.0'
    expect { described_class.new.resolve! }.to raise_error(/does not match selected version/)
    expect(File.read(environment_file)).to eq('')
  end

  it 'rejects a missing specification before recording a release', :aggregate_failures do
    ENV['GEMSPEC'] = 'missing.gemspec'
    expect { described_class.new.resolve! }.to raise_error(ArgumentError, /existing file/)
    expect(File.read(environment_file)).to eq('')
  end

  it 'rejects non-default-branch publication before configuring Git' do
    ENV['GITHUB_REF'] = 'refs/heads/topic'
    expect { described_class.new.capture! }.to raise_error(/default branch/)
  end

  it 'rejects dirty dependencies before evaluating the gemspec or exporting context', :aggregate_failures do
    File.write('fixture.gemspec', "raise 'gemspec must not load'\n")
    allow(git).to receive(:check_clean!).and_raise('Release requires a clean checkout')
    expect { described_class.new.capture! }.to raise_error(/clean checkout/)
    expect(git).not_to have_received(:check_current!)
    expect(File.read(environment_file)).to eq('')
  end

  it 'rejects an existing tag before recording the prepared version' do
    allow(git).to receive(:check_tag!).and_raise('Release tag already exists')
    expect { described_class.new.resolve! }.to raise_error(/tag already exists/)
  end

  it 'rejects an already published prepared version before staging or exporting it', :aggregate_failures do
    File.write('version.rb', "VERSION = '2.0.0'\n")
    http = instance_double(Net::HTTP)
    response = instance_double(Net::HTTPResponse, code: '200')
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:get).with('/api/v2/rubygems/fixture/versions/2.0.0.json').and_return(response)
    expect { described_class.new.resolve! }.to raise_error(/fixture 2.0.0.*already published/)
    expect(git).not_to have_received(:stage_changes!)
    expect(File.read(environment_file)).to eq('')
  end

  it 'uses the supplied destination for version checks without contacting RubyGems or enabling its authentication' do
    destination = instance_double(RubyGemRelease::Destination, check_version!: nil, authentication: nil)
    described_class.new.resolve!(destination: destination)
    expect(destination).to have_received(:check_version!).with(name: 'fixture', version: '1.2.3')
    expect(Net::HTTP).not_to have_received(:start)
    expect(File.read(environment_file)).to include("RELEASE_VERSION=1.2.3\n", "RELEASE_AUTHENTICATION=\n")
  end

  it 'rejects unsupported automatic authentication before version checks or staging' do
    destination = instance_double(RubyGemRelease::Destination, authentication: 'unsupported', check_version!: nil)
    expect { described_class.new.resolve!(destination: destination) }.to raise_error(ArgumentError, /unsupported destination authentication/)
    expect(destination).not_to have_received(:check_version!)
    expect(git).not_to have_received(:stage_changes!)
    expect(File.read(environment_file)).to eq('')
  end

  context 'with a provider-neutral environment' do
    let(:values) { { 'RELEASE_REF' => 'refs/heads/master', 'DEFAULT_BRANCH' => 'master', 'RELEASE_DIRECTORY' => directory } }
    let(:provider) { RubyGemRelease::ExecutionProvider.new(environment: values) }

    it 'captures and resolves without using Actions files or RubyGems' do
      File.write('other.gemspec', "raise 'unselected gemspec must not load'\n")
      values['INPUT_GEMSPEC'] = 'fixture.gemspec'
      destination = instance_double(RubyGemRelease::Destination, check_version!: nil, authentication: nil)
      instance = described_class.new(provider: provider)
      instance.capture!
      File.write('version.rb', "VERSION = '2.0.0'\n")
      instance.resolve!(destination: destination)
      expect(values).to include('RELEASE_PREVIOUS_VERSION' => '1.2.3', 'RELEASE_VERSION' => '2.0.0', 'RELEASE_DIRECTORY' => directory)
      expect(File).to exist(values.fetch('RELEASE_STATE'))
      expect(git).to have_received(:configure!).with(name: 'ruby-gem-release', email: 'ruby-gem-release@localhost')
      expect(destination).to have_received(:check_version!).with(name: 'fixture', version: '2.0.0')
      expect(Net::HTTP).not_to have_received(:start)
      expect(File.read(environment_file)).to eq('')
    end

    it 'checks the provider ref rather than an unrelated GitHub ref' do
      values['RELEASE_REF'] = 'refs/heads/topic'
      expect { described_class.new(provider: provider).capture! }.to raise_error(/default branch/)
      expect(git).not_to have_received(:configure!)
    end
  end

  context 'when configuring composite action inputs' do
    before do
      ENV.update('INPUT_GEMSPEC' => 'fixture.gemspec', 'DEFAULT_BRANCH' => 'master',
                 'GIT_USER_NAME' => 'Fixture', 'GIT_USER_EMAIL' => 'fixture@example.com', 'RUBYGEMS_OWNER' => '123')
    end

    it 'exports inputs for later action steps' do
      described_class.new.configure!
      expect(File.read(environment_file)).to include("INPUT_GEMSPEC=fixture.gemspec\n", "RUBYGEMS_OWNER=123\n", "TZ=UTC\n")
    end

    it 'exports the configured timezone for subsequent steps' do
      ENV['TZ'] = 'America/New_York'
      described_class.new.configure!
      expect(File.read(environment_file)).to include("TZ=America/New_York\n")
    end

    it 'rejects an invalid timezone before exporting inputs', :aggregate_failures do
      ENV['TZ'] = 'Unknown/Zone'
      expect { described_class.new.configure! }.to raise_error(ArgumentError, /timezone/)
      expect(File.read(environment_file)).to eq('')
    end

    it 'rejects environment-file injection before exporting any inputs', :aggregate_failures do
      ENV['GIT_USER_EMAIL'] = "fixture@example.com\nINJECTED=value"
      expect { described_class.new.configure! }.to raise_error(ArgumentError, /line breaks/)
      expect(File.read(environment_file)).to eq('')
    end
  end
end
