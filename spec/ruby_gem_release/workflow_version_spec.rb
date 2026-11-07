# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/workflow'
require 'tmpdir'

RSpec.describe RubyGemRelease::Workflow do
  let(:directory) { Dir.mktmpdir }
  let(:environment_file) { File.join(directory, 'environment') }
  let(:git) { instance_double(RubyGemRelease::SourceControl::Git, configure!: nil, check_current!: nil, check_tag!: nil, head: 'initial-commit') }

  around do |example|
    original = ENV.to_h
    ENV.update('GITHUB_ENV' => environment_file, 'INPUT_VERSION' => '', 'DRY_RUN' => 'true')
    ENV.delete('GEMSPEC')
    ENV.delete('INPUT_GEMSPEC')
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
    ENV.update('DRY_RUN' => 'false', 'GITHUB_REF' => 'refs/heads/topic', 'DEFAULT_BRANCH' => 'master')
    expect { described_class.new.capture! }.to raise_error(/default branch/)
  end

  it 'rejects an existing tag before recording the prepared version' do
    allow(git).to receive(:check_tag!).and_raise('Release tag already exists')
    expect { described_class.new.resolve! }.to raise_error(/tag already exists/)
  end
end
