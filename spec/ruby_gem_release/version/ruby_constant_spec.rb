# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubyGemRelease::Version::RubyConstant do
  let(:directory) { Dir.mktmpdir }
  let(:version_file) { File.join(directory, 'version.rb') }
  let(:version) { described_class.new(path: version_file, constant: 'VERSION') }

  after { FileUtils.remove_entry(directory) }

  before do
    File.write(version_file, "module Example\n  VERSION = '1.2.3'\nend\n")
  end

  it 'reads a version without evaluating the file' do
    File.write(version_file, "raise 'must not run'\nVERSION = '1.2.3'\n")
    expect(version.read).to eq('1.2.3')
  end

  it 'sets a version while preserving surrounding content', :aggregate_failures do
    expect(version.set!('2.0.0')).to eq('2.0.0')
    expect(File.read(version_file)).to eq("module Example\n  VERSION = '2.0.0'\nend\n")
  end

  it 'repeats an increment from a fixed release version without incrementing twice' do
    2.times { expect(version.increment!(from: '1.2.3')).to eq('1.2.4') }
    expect(version.read).to eq('1.2.4')
  end

  it 'rejects invalid versions without changing the file', :aggregate_failures do
    original = File.read(version_file)
    expect { version.set!('1.02.3') }.to raise_error(ArgumentError, /invalid version/)
    expect(File.read(version_file)).to eq(original)
  end

  %w[patch minor major].zip(%w[1.2.4 1.3.0 2.0.0]).each do |part, version|
    it "increments #{part} and resets lower components", :aggregate_failures do
      strategy = described_class.new(path: version_file, constant: 'VERSION')
      expect(strategy.next_version(part: part)).to eq(version)
      expect(File.read(version_file)).to include("VERSION = '1.2.3'")
      expect(strategy.increment!(part: part)).to eq(version)
      expect(File.read(version_file)).to include("VERSION = '#{version}'")
    end
  end

  it 'defaults to a patch bump' do
    expect(version.increment!).to eq('1.2.4')
  end

  it 'rejects unknown bump parts' do
    expect { version.increment!(part: 'prerelease') }.to raise_error(ArgumentError, /bump part/)
  end

  it 'rejects ambiguous assignments without changing the file', :aggregate_failures do
    File.write(version_file, "VERSION = '1.2.3'\nVERSION = '2.0.0'\n")
    original = File.read(version_file)
    expect { version.set!('3.0.0') }.to raise_error(ArgumentError, /exactly one/)
    expect(File.read(version_file)).to eq(original)
  end

  it 'rejects an invalid constant name' do
    expect { described_class.new(path: version_file, constant: 'Version::VALUE') }
      .to raise_error(ArgumentError, /constant name/)
  end
end
