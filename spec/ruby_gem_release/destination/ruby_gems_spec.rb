# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/destination/ruby_gems'
require 'ruby-gem-release/package/ruby_gem'
require 'tmpdir'

RSpec.describe RubyGemRelease::Destination::RubyGems do
  let(:directory) { Dir.mktmpdir }
  let(:artifacts) { File.join(directory, 'artifacts') }
  let(:package) { RubyGemRelease::Package::RubyGem.new(gemspec: 'fixture.gemspec', directory: artifacts) }
  let(:release) { RubyGemRelease::Release.new(version: '1.2.3', gemspec_version: '1.2.3', date: Date.today) }
  let(:response) { instance_double(Net::HTTPResponse, code: '404', body: '{}') }

  around do |example|
    Dir.chdir(directory) { example.run }
  ensure
    FileUtils.remove_entry(directory)
  end

  before do
    File.write('fixture.gemspec', <<~RUBY)
      Gem::Specification.new do |spec|
        spec.name = 'release-fixture'
        spec.version = '1.2.3'
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

  it 'publishes exactly the built archive without rebuilding or consulting an edited gemspec' do
    path = package.build!(release)
    File.write('fixture.gemspec', "raise 'must use built metadata'\n")
    status = instance_double(Process::Status, success?: true)
    allow(Open3).to receive(:capture3).with(Gem.ruby, '-S', 'gem', 'push', path).and_return(['published', '', status])
    expect(described_class.new.publish!(release, package: package)).to eq('published')
    expect(Open3).to have_received(:capture3).once
  end

  it 'accepts only an unpublished version' do
    expect { described_class.new.check_version!(name: 'release-fixture', version: '1.2.3') }.not_to raise_error
  end

  it 'rejects an existing version without building or uploading' do
    allow(response).to receive(:code).and_return('200')
    expect { described_class.new.check_version!(name: 'release-fixture', version: '1.2.3') }.to raise_error(/release-fixture 1.2.3.*already published.*recovery/)
    expect(File).not_to exist(artifacts)
    expect(Net::HTTP).to have_received(:start).once
  end

  it 'rejects unexpected responses rather than treating them as missing versions' do
    %w[301 401 429 503].each do |code|
      allow(response).to receive(:code).and_return(code)
      expect { described_class.new.check_version!(name: 'release-fixture', version: '1.2.3') }.to raise_error(/Cannot check RubyGems.*HTTP #{code}/)
    end
  end

  it 'stops on connection and timeout failures without retrying' do
    [Net::OpenTimeout, SocketError, OpenSSL::SSL::SSLError].each do |error|
      allow(Net::HTTP).to receive(:start).and_raise(error, 'unavailable')
      expect { described_class.new.check_version!(name: 'release-fixture', version: '1.2.3') }.to raise_error(/Cannot check RubyGems.*verify connectivity/)
    end
    expect(Net::HTTP).to have_received(:start).exactly(3).times
  end

  it 'rejects invalid names before making a registry request' do
    expect { described_class.new.check_version!(name: '../other', version: '1.2.3') }.to raise_error(/Invalid package name/)
    expect(Net::HTTP).not_to have_received(:start)
  end

  it 'refuses to upload a built artifact that has already been published' do
    package.build!(release)
    allow(response).to receive(:code).and_return('200')
    allow(Open3).to receive(:capture3).and_raise('Unexpected uploader')
    expect { described_class.new.publish!(release, package: package) }.to raise_error(/checksum differs or is unavailable/)
    expect(Open3).not_to have_received(:capture3)
  end

  it 'does not upload again when the registry proves that the exact archive is published' do
    path = package.build!(release)
    allow(response).to receive_messages(code: '200', body: JSON.generate('sha' => Digest::SHA256.file(path).hexdigest))
    allow(Open3).to receive(:capture3).and_raise('Unexpected uploader')
    described_class.new.publish!(release, package: package)
    expect(Open3).not_to have_received(:capture3)
  end

  it 'refuses a different published checksum or malformed readback without uploading' do
    package.build!(release)
    allow(response).to receive(:code).and_return('200')
    allow(Open3).to receive(:capture3).and_raise('Unexpected uploader')
    allow(response).to receive(:body).and_return(JSON.generate('sha' => '0' * 64))
    expect { described_class.new.publish!(release, package: package) }.to raise_error(/checksum differs/)
    allow(response).to receive(:body).and_return('invalid')
    expect { described_class.new.publish!(release, package: package) }.to raise_error(JSON::ParserError)
    expect(Open3).not_to have_received(:capture3)
  end

  it 'rejects changed artifacts before invoking an uploader or registry request' do
    package.build!(release)
    File.write(File.join(artifacts, 'release.gem'), 'changed')
    allow(Open3).to receive(:capture3).and_raise('Unexpected uploader')
    expect { described_class.new.publish!(release, package: package) }.to raise_error(/artifact changed/)
    expect(Net::HTTP).not_to have_received(:start)
    expect(Open3).not_to have_received(:capture3)
  end

  it 'rejects a custom package returning an artifact for a different version' do
    path = package.build!(release)
    custom = instance_double(RubyGemRelease::Package::RubyGem, artifact: path)
    expect { described_class.new.publish!(release.with_version('2.0.0'), package: custom) }.to raise_error(/Package version does not match release/)
    expect(Net::HTTP).not_to have_received(:start)
  end

  it 'propagates an upload failure without retrying' do
    path = package.build!(release)
    status = instance_double(Process::Status, success?: false)
    allow(Open3).to receive(:capture3).with(Gem.ruby, '-S', 'gem', 'push', path).and_return(['', 'upload failed', status])
    expect { described_class.new.publish!(release, package: package) }.to raise_error(/Destination command failed.*upload failed/)
    expect(Open3).to have_received(:capture3).once
  end

  it 'accepts a failed push only when readback proves the exact archive was published' do
    path = package.build!(release)
    allow(response).to receive(:code).and_return('404', '200')
    allow(response).to receive(:body).and_return(JSON.generate('sha' => Digest::SHA256.file(path).hexdigest))
    allow(Open3).to receive(:capture3).with(Gem.ruby, '-S', 'gem', 'push', path)
                                      .and_return(['', 'version already published', instance_double(Process::Status, success?: false)])
    expect { described_class.new.publish!(release, package: package) }.not_to raise_error
    expect(Open3).to have_received(:capture3).once
    expect(Net::HTTP).to have_received(:start).twice
  end
end
