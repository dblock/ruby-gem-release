# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/package/ruby_gem'
require 'tmpdir'

RSpec.describe RubyGemRelease::Package::RubyGem do
  let(:directory) { Dir.mktmpdir }
  let(:artifacts) { File.join(directory, 'artifacts') }
  let(:package) { described_class.new(gemspec: 'fixture.gemspec', directory: artifacts) }
  let(:release) { RubyGemRelease::Release.new(version: '1.2.3', gemspec_version: '1.2.3', date: Date.today) }

  around do |example|
    original = ENV.to_h
    ENV.delete('GEMSPEC_PATH')
    ENV.delete('SOURCE_DATE_EPOCH')
    Dir.chdir(directory) { example.run }
  ensure
    ENV.replace(original)
    FileUtils.remove_entry(directory)
  end

  before do
    File.write('fixture.gemspec', <<~RUBY)
      require_relative 'version'
      Gem::Specification.new do |spec|
        spec.name = 'release-fixture'
        spec.version = VERSION
        spec.summary = 'Release fixture'
        spec.authors = ['Fixture']
        spec.files = ['version.rb']
      end
    RUBY
    File.write('version.rb', "VERSION = '1.2.3'\n")
  end

  it 'builds a real archive and reopens the same verified artifact', :aggregate_failures do
    path = package.build!(release)
    reopened = described_class.new(gemspec: 'fixture.gemspec', directory: artifacts)
    expect(reopened.artifact(release)).to eq(path)
    expect(Gem::Package.new(path).spec.version.to_s).to eq('1.2.3')
    expect(File.binread(path)).to eq(File.binread(File.join(artifacts, 'release.gem')))
  end

  it 'uses the built archive identity after custom preparation' do
    File.write('fixture.gemspec', File.read('fixture.gemspec').sub('release-fixture', 'renamed-fixture'))
    path = package.build!(release)
    expect(File.basename(path)).to eq('renamed-fixture-1.2.3.gem')
    expect(Gem::Package.new(path).spec.name).to eq('renamed-fixture')
  end

  it 'rebuilds reproducibly with a fixed timestamp instead of depending on a previous archive' do
    allow(Open3).to receive(:capture3).and_call_original
    path = package.build!(release)
    digest = Digest::SHA256.file(path).hexdigest
    File.write(File.join(artifacts, 'release.gem'), 'partial output')
    File.write(File.join(artifacts, 'release.json'), 'partial output')
    reopened = described_class.new(gemspec: 'fixture.gemspec', directory: artifacts)
    expect(reopened.build!(release)).to eq(path)
    expect(Digest::SHA256.file(path).hexdigest).to eq(digest)
    expect(Open3).to have_received(:capture3).with(hash_including('SOURCE_DATE_EPOCH' => '315619200'), Gem.ruby, '-S', 'gem', 'build', anything, '--output', anything).twice
  end

  it 'refuses a manifest naming another gem even when its checksum matches' do
    package.build!(release)
    path = File.join(artifacts, 'release.json')
    manifest = JSON.parse(File.read(path)).merge('name' => 'different-gem')
    File.write(path, JSON.generate(manifest))
    reopened = described_class.new(gemspec: 'fixture.gemspec', directory: artifacts)
    expect { reopened.artifact(release) }.to raise_error(/metadata differs/)
  end

  it 'rejects an archive whose version differs from the release' do
    expect { package.build!(release.with_version('2.0.0')) }.to raise_error(/Built version 1.2.3 does not match 2.0.0/)
  end

  it 'rejects changed artifacts when reopening them', :aggregate_failures do
    package.build!(release)
    File.write(File.join(artifacts, 'release.gem'), 'changed')
    expect { package.artifact(release) }.to raise_error(/artifact changed/)
  end

  it 'reads a newly edited version without reusing loaded constants', :aggregate_failures do
    expect(package.version).to eq('1.2.3')
    File.write('version.rb', "VERSION = '2.0.0'\n")
    expect(package.version).to eq('2.0.0')
  end

  it 'rejects ambiguous specifications' do
    File.write('other.gemspec', '')
    expect { described_class.new(directory: artifacts) }.to raise_error(ArgumentError, /exactly one root gemspec/)
  end
end
