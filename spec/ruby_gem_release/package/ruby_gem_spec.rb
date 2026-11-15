# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/package/ruby_gem'
require 'ruby-gem-release/package/content_audit'
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

  it 'retains Java platform identity in the filename and digest manifest' do
    File.write('fixture.gemspec', File.read('fixture.gemspec').sub('spec.version = VERSION', "spec.version = VERSION\n  spec.platform = 'java'"))
    path = package.build!(release)
    expect(File.basename(path)).to eq('release-fixture-1.2.3-java.gem')
    expect(JSON.parse(File.read(File.join(artifacts, 'release.json'))).fetch('platform')).to eq('java')
    reopened = described_class.new(gemspec: 'fixture.gemspec', directory: artifacts)
    expect(reopened.artifact(release)).to eq(path)
    manifest = JSON.parse(File.read(File.join(artifacts, 'release.json'))).merge('platform' => 'ruby')
    File.write(File.join(artifacts, 'release.json'), JSON.generate(manifest))
    expect { reopened.artifact(release) }.to raise_error(/metadata differs/)
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

  context 'with source-aware content auditing' do
    let(:audit) { RubyGemRelease::Package::ContentAudit.new(expected_files: -> { ['version.rb'] }, root: directory) }
    let(:package) { described_class.new(gemspec: 'fixture.gemspec', directory: artifacts, audit: audit) }

    before do
      commands = [%w[init --quiet], %w[add version.rb], ['-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'commit', '--quiet', '-m', 'Initial']]
      commands.each do |arguments|
        output, error, status = Open3.capture3('git', *arguments)
        raise "#{output}\n#{error}" unless status.success?
      end
    end

    it 'checks built and reopened archives against the exact Git bytes' do
      path = package.build!(release)
      expect(audit.verify!(path)).to eq(path)
      reopened = described_class.new(gemspec: 'fixture.gemspec', directory: artifacts, audit: audit)
      expect(reopened.artifact(release)).to eq(path)
      File.write('version.rb', "VERSION = '1.2.3' # changed\n")
      expect { package.build!(release) }.to raise_error(/bytes differ from Git source: version.rb/)
    end

    it 'rejects accidentally shipped developer files and missing required files' do
      path = package.build!(release)
      missing = RubyGemRelease::Package::ContentAudit.new(expected_files: ['version.rb', 'README.md'])
      expect { missing.verify!(path) }.to raise_error(/missing.*README.md/)
      File.write('developer.txt', 'private notes')
      File.write('fixture.gemspec', File.read('fixture.gemspec').sub("['version.rb']", "['version.rb', 'developer.txt']"))
      expect { package.build!(release) }.to raise_error(/unexpected.*developer.txt/)
    end

    it 'requires generated files to be explicitly expected and exempts only their source bytes' do
      path = package.build!(release)
      File.write('generated.bin', "\x00\xFF".b)
      File.write('fixture.gemspec', File.read('fixture.gemspec').sub("['version.rb']", "['version.rb', 'generated.bin']"))
      generated = RubyGemRelease::Package::ContentAudit.new(expected_files: ['version.rb', 'generated.bin'], generated: ['generated.bin'])
      allowed = described_class.new(gemspec: 'fixture.gemspec', directory: artifacts, audit: generated)
      expect { allowed.build!(release) }.not_to raise_error
      expect { generated.verify!(path) }.not_to raise_error
      invalid = RubyGemRelease::Package::ContentAudit.new(expected_files: ['version.rb'], generated: ['generated.bin'])
      expect { invalid.verify!(path) }.to raise_error(/Generated paths must be included/)
    end

    it 'rejects unsafe or duplicate expectations and unavailable source commits' do
      ['../version.rb', '/version.rb', '', "bad\nname"].each do |unsafe|
        invalid = RubyGemRelease::Package::ContentAudit.new(expected_files: [unsafe])
        expect { invalid.verify!(package.build!(release)) }.to raise_error(ArgumentError, /Unsafe file path/)
      end
      duplicate = RubyGemRelease::Package::ContentAudit.new(expected_files: ['version.rb'] * 2)
      expect { duplicate.verify!(package.build!(release)) }.to raise_error(ArgumentError, /Duplicate/)
      unavailable = RubyGemRelease::Package::ContentAudit.new(expected_files: ['version.rb'], source: 'not-a-commit')
      expect { unavailable.verify!(package.build!(release)) }.to raise_error(/Cannot verify Git source/)
    end
  end
end
