# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubyGemRelease::Tasks do
  let(:directory) { Dir.mktmpdir }
  let(:version_file) { File.join(directory, 'version.rb') }

  around do |example|
    original = Rake.application
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = original
  end

  after { FileUtils.remove_entry(directory) }

  def invoke(name, *args)
    Rake::Task["release:version:#{name}"].invoke(*args)
  end

  before do
    File.write(version_file, "module Example\n  VERSION = '1.2.3'\nend\n")
    described_class.install(version_file: version_file, version_constant: 'VERSION')
  end

  it 'reads a version without evaluating the file' do
    File.write(version_file, "raise 'must not run'\nVERSION = '1.2.3'\n")
    expect { invoke('read') }.to output("1.2.3\n").to_stdout
  end

  it 'sets a version while preserving surrounding content', :aggregate_failures do
    expect { invoke('set', '2.0.0') }.to output("2.0.0\n").to_stdout
    expect(File.read(version_file)).to eq("module Example\n  VERSION = '2.0.0'\nend\n")
  end

  it 'rejects invalid versions without changing the file', :aggregate_failures do
    original = File.read(version_file)
    expect { invoke('set', '1.02.3') }.to raise_error(ArgumentError, /invalid version/)
    expect(File.read(version_file)).to eq(original)
  end

  %w[patch minor major].zip(%w[1.2.4 1.3.0 2.0.0]).each do |part, version|
    it "bumps #{part} and resets lower components", :aggregate_failures do
      expect { invoke('bump', part) }.to output("#{version}\n").to_stdout
      expect(File.read(version_file)).to include("VERSION = '#{version}'")
    end
  end

  it 'defaults to a patch bump' do
    expect { invoke('bump') }.to output("1.2.4\n").to_stdout
  end

  it 'rejects unknown bump parts' do
    expect { invoke('bump', 'prerelease') }.to raise_error(ArgumentError, /bump part/)
  end

  it 'rejects ambiguous assignments without changing the file', :aggregate_failures do
    File.write(version_file, "VERSION = '1.2.3'\nVERSION = '2.0.0'\n")
    original = File.read(version_file)
    expect { invoke('set', '3.0.0') }.to raise_error(ArgumentError, /exactly one/)
    expect(File.read(version_file)).to eq(original)
  end

  it 'rejects an invalid constant name' do
    expect { described_class.install(version_file: version_file, version_constant: 'Version::VALUE') }
      .to raise_error(ArgumentError, /constant name/)
  end
end
