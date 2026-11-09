# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/workflow/environment'
require 'tmpdir'

RSpec.describe RubyGemRelease::Workflow::Environment do
  let(:directory) { Dir.mktmpdir }
  let(:environment_file) { File.join(directory, 'environment') }
  let(:git) do
    instance_double(RubyGemRelease::SourceControl::Git, configure!: nil, check_clean!: nil, check_current!: nil, check_tag!: nil,
                                                        stage_changes!: nil, head: 'initial-commit', timestamp: '1794054896')
  end

  around do |example|
    original = ENV.to_h
    ENV.update('GITHUB_ACTIONS' => 'true', 'GITHUB_ENV' => environment_file, 'INPUT_VERSION' => '', 'GITHUB_REF' => 'refs/heads/master', 'DEFAULT_BRANCH' => 'master', 'RUNNER_TEMP' => directory)
    ENV.delete('GEMSPEC')
    ENV.delete('INPUT_GEMSPEC')
    ENV.delete('TZ')
    ENV.delete('SOURCE_DATE_EPOCH')
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

  it 'exports the captured source commit timestamp rather than the workflow time' do
    ENV['SOURCE_DATE_EPOCH'] = ' '
    described_class.new.capture!
    expect(File.read(environment_file)).to include("SOURCE_DATE_EPOCH=1794054896\n")
    expect(git).to have_received(:timestamp).with('initial-commit')
  end

  it 'preserves an explicitly supplied source timestamp without consulting Git timestamps' do
    ENV['SOURCE_DATE_EPOCH'] = ' 1700000000 '
    described_class.new.capture!
    expect(File.read(environment_file)).to include("SOURCE_DATE_EPOCH=1700000000\n")
    expect(git).not_to have_received(:timestamp)
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

  it 'enforces the persisted semantic selection even when no explicit version was supplied' do
    ENV['RELEASE_INITIAL_COMMIT'] = 'a' * 40
    decision = RubyGemRelease::SemanticRelease::Decision.new(head: 'a' * 40, last_release: nil, commits: [],
                                                             release_type: 'minor', version: '2.0.0', notes: 'Generated.')
    expect { described_class.new.resolve!(analysis: decision) }.to raise_error(ArgumentError, /differs/)
    expect(git).not_to have_received(:stage_changes!)
    File.write('version.rb', "VERSION = '2.0.0'\n")
    described_class.new.resolve!(analysis: decision)
    expect(File.read(environment_file)).to include("RELEASE_VERSION=2.0.0\n")
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

  it 'leaves existing tags and publication checks to the publishing tasks' do
    allow(git).to receive(:check_tag!).and_raise('Release tag already exists')
    File.write('version.rb', "VERSION = '2.0.0'\n")
    described_class.new.resolve!
    expect(git).not_to have_received(:check_tag!)
    expect(Net::HTTP).not_to have_received(:start)
    expect(git).to have_received(:stage_changes!)
    expect(File.read(environment_file)).to include("RELEASE_VERSION=2.0.0\n")
  end

  it 'uses the supplied destination authentication policy without contacting RubyGems' do
    destination = instance_double(RubyGemRelease::Destination, check_version!: nil, authentication: nil)
    described_class.new.resolve!(destination: destination)
    expect(destination).not_to have_received(:check_version!)
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

    it 'captures the explicitly configured package instead of rediscovering root specifications' do
      File.write('other.gemspec', "raise 'unselected gemspec must not load'\n")
      package = RubyGemRelease::Package::RubyGem.new(gemspec: 'fixture.gemspec', directory: directory)
      described_class.new(provider: provider).capture!(package: package)
      expect(values).to include('GEMSPEC' => package.gemspec, 'RELEASE_PREVIOUS_VERSION' => '1.2.3')
      expect(git).to have_received(:check_clean!)
      expect(git).to have_received(:check_current!).with(have_attributes(version: '1.2.3'), allow_ancestor: true)
    end

    it 'captures custom package metadata without requiring a gemspec accessor' do
      package = Struct.new(:version).new('2.3.4')
      values['GEMSPEC'] = 'stale.gemspec'
      described_class.new(provider: provider).capture!(package: package)
      expect(values).to include('GEMSPEC' => '', 'RELEASE_PREVIOUS_VERSION' => '2.3.4')
    end

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
      expect(destination).not_to have_received(:check_version!)
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
