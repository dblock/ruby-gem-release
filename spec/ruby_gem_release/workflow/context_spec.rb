# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/workflow/context'
require 'tmpdir'

RSpec.describe RubyGemRelease::Workflow::Context do
  let(:directory) { Dir.mktmpdir }
  let(:environment_file) { File.join(directory, 'environment') }
  let(:git) { instance_double(RubyGemRelease::SourceControl::Git, configure!: nil, check_current!: nil, check_tag!: nil, head: 'initial-commit') }

  around do |example|
    original = ENV.to_h
    ENV.update('GITHUB_ENV' => environment_file, 'INPUT_VERSION' => '', 'GITHUB_REF' => 'refs/heads/master', 'DEFAULT_BRANCH' => 'master')
    ENV.delete('GEMSPEC')
    ENV.delete('INPUT_GEMSPEC')
    ENV.delete('TZ')
    Dir.chdir(directory) { example.run }
  ensure
    ENV.replace(original)
    FileUtils.remove_entry(directory)
  end

  before do
    File.write('fixture.gemspec', "require_relative 'version'\nGem::Specification.new { |spec| spec.version = VERSION }\n")
    File.write('version.rb', "VERSION = '1.2.3'\n")
    File.write(environment_file, '')
    allow(RubyGemRelease::SourceControl::Git).to receive(:new).and_return(git)
  end

  it 'retains the initial version while resolving callback edits', :aggregate_failures do
    described_class.new.capture!
    File.write('version.rb', "VERSION = '2.0.0'\n")
    described_class.new.resolve!
    expect(File.read(environment_file)).to include("RELEASE_PREVIOUS_VERSION=1.2.3\n", "RELEASE_VERSION=2.0.0\n", "RELEASE_INITIAL_COMMIT=initial-commit\n")
  end

  it 'defaults the calendar date to UTC rather than the server timezone' do
    allow(Time).to receive(:now).and_return(Time.new(2026, 11, 7, 23, 30, 0, '-05:00'))
    described_class.new.capture!
    expect(File.read(environment_file)).to include("RELEASE_DATE=2026-11-08\n")
  end

  it 'retains the captured calendar date when a later phase crosses midnight' do # rubocop:disable RSpec/ExampleLength -- Advance the clock only after gemspec loading and capture.
    ENV['TZ'] = 'America/New_York'
    allow(Time).to receive(:now).and_return(Time.utc(2026, 11, 8, 4, 30))
    described_class.new.capture!
    allow(Time).to receive(:now).and_return(Time.utc(2026, 11, 8, 5, 30))
    described_class.new.resolve!
    expect(File.readlines(environment_file).grep(/\ARELEASE_DATE=/)).to eq(["RELEASE_DATE=2026-11-07\n"])
  end

  it 'uses the configured timezone across midnight and daylight saving changes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- Check winter and summer dates for the same UTC clock time.
    ENV['TZ'] = 'America/New_York'
    [[Time.utc(2026, 11, 8, 4, 30), '2026-11-07'], [Time.utc(2026, 7, 8, 4, 30), '2026-07-08']].each do |instant, date|
      File.write(environment_file, '')
      allow(Time).to receive(:now).and_return(instant)
      described_class.new.capture!
      expect(File.read(environment_file)).to include("RELEASE_DATE=#{date}\n")
    end
  end

  it 'rejects unknown timezones and traversal before configuring Git or exporting context', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- Check unsupported and unsafe timezone identifiers.
    ['Unknown/Zone', '../UTC', '', '-05:00'].each do |timezone|
      ENV['TZ'] = timezone
      expect { described_class.new.capture! }.to raise_error(ArgumentError, /timezone/)
    end
    expect(git).not_to have_received(:configure!)
    expect(File.read(environment_file)).to eq('')
  end

  it 'rejects an expected-version mismatch before recording a release', :aggregate_failures do
    ENV['INPUT_VERSION'] = '2.0.0'
    expect { described_class.new.resolve! }.to raise_error(/does not match expected version/)
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

  it 'rejects an existing tag before recording the prepared version' do
    allow(git).to receive(:check_tag!).and_raise('Release tag already exists')
    expect { described_class.new.resolve! }.to raise_error(/tag already exists/)
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
