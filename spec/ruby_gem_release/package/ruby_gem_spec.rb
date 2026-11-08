# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/package/ruby_gem'
require 'tmpdir'

RSpec.describe RubyGemRelease::Package::RubyGem do
  let(:directory) { Dir.mktmpdir }
  let(:artifacts) { File.join(directory, 'artifacts') }
  let(:package) { described_class.new(gemspec: 'fixture.gemspec', directory: artifacts) }
  let(:release) { RubyGemRelease::Release.new(version: '1.2.3', previous_version: '1.2.3', date: Date.today) }
  let(:response) { instance_double(Net::HTTPResponse, code: '404') }

  around do |example|
    original = ENV.delete('GEMSPEC')
    Dir.chdir(directory) { example.run }
  ensure
    ENV['GEMSPEC'] = original if original
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
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:start).with('rubygems.org', 443, use_ssl: true, open_timeout: 10, read_timeout: 30, max_retries: 0).and_yield(http)
    allow(http).to receive(:get).with('/api/v2/rubygems/release-fixture/versions/1.2.3.json').and_return(response)
  end

  it 'builds a real archive and reopens the same verified artifact', :aggregate_failures do
    path = package.build!(release)
    reopened = described_class.new(gemspec: 'fixture.gemspec', directory: artifacts)
    expect(reopened.artifact(release)).to eq(path)
    expect(Gem::Package.new(path).spec.version.to_s).to eq('1.2.3')
    expect(File.binread(path)).to eq(File.binread(File.join(artifacts, 'release.gem')))
  end

  it 'publishes exactly the built archive without rebuilding', :aggregate_failures do
    path = package.build!(release)
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).with(Gem.ruby, '-S', 'gem', 'push', path).and_return(['published', '', status])
    expect(package.publish!(release)).to eq('published')
    expect(Open3).to have_received(:capture3).once
  end

  context 'when checking published versions' do
    it 'accepts only an unpublished version' do
      expect { package.check_version!('1.2.3') }.not_to raise_error
    end

    it 'rejects an existing version without building or uploading', :aggregate_failures do
      allow(response).to receive(:code).and_return('200')
      expect { package.check_version!('1.2.3') }.to raise_error(/release-fixture 1.2.3.*already published.*recovery/)
      expect(File).not_to exist(artifacts)
      expect(Net::HTTP).to have_received(:start).once
    end

    it 'checks the specified version rather than a newer gemspec version' do
      File.write('version.rb', "VERSION = '2.0.0'\n")
      expect { package.check_version!('1.2.3') }.not_to raise_error
    end

    it 'reads the current gem name after custom preparation' do
      File.write('fixture.gemspec', File.read('fixture.gemspec').sub('release-fixture', 'renamed-fixture'))
      http = instance_double(Net::HTTP)
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(http).to receive(:get).with('/api/v2/rubygems/renamed-fixture/versions/1.2.3.json').and_return(response)
      expect { package.check_version!('1.2.3') }.not_to raise_error
    end

    it 'rejects unexpected responses rather than treating them as missing versions', :aggregate_failures do
      %w[301 401 429 503].each do |code|
        allow(response).to receive(:code).and_return(code)
        expect { package.check_version!('1.2.3') }.to raise_error(/Cannot check RubyGems.*HTTP #{code}/)
      end
    end

    it 'stops on connection and timeout failures without retrying', :aggregate_failures do
      [Net::OpenTimeout, SocketError, OpenSSL::SSL::SSLError].each do |error|
        allow(Net::HTTP).to receive(:start).and_raise(error, 'unavailable')
        expect { package.check_version!('1.2.3') }.to raise_error(/Cannot check RubyGems.*verify connectivity/)
      end
      expect(Net::HTTP).to have_received(:start).exactly(3).times
    end

    it 'refuses to upload a built artifact that has already been published', :aggregate_failures do
      package.build!(release)
      allow(response).to receive(:code).and_return('200')
      allow(Open3).to receive(:capture3).and_raise('Unexpected uploader')
      expect { package.publish!(release) }.to raise_error(/already published/)
      expect(Open3).not_to have_received(:capture3)
    end
  end

  it 'rejects an archive whose version differs from the release' do
    expect { package.build!(release.with_version('2.0.0')) }.to raise_error(/Built version 1.2.3 does not match 2.0.0/)
  end

  it 'rejects changed artifacts before invoking an uploader', :aggregate_failures do
    package.build!(release)
    File.write(File.join(artifacts, 'release.gem'), 'changed')
    allow(Open3).to receive(:capture3).and_raise('Unexpected uploader')
    expect { package.publish!(release) }.to raise_error(/artifact changed/)
  end

  it 'propagates an upload failure without retrying', :aggregate_failures do
    path = package.build!(release)
    status = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture3).with(Gem.ruby, '-S', 'gem', 'push', path).and_return(['', 'upload failed', status])
    expect { package.publish!(release) }.to raise_error(/upload failed/)
    expect(Open3).to have_received(:capture3).once
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
