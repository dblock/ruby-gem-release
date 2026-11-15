# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/destination/ruby_gems'
require 'ruby-gem-release/package/ruby_gem'
require 'ruby-gem-release/package/prebuilt'
require 'ruby-gem-release/package/collection'
require 'tmpdir'

RSpec.describe RubyGemRelease::Destination::RubyGems do
  let(:directory) { Dir.mktmpdir }
  let(:release) { RubyGemRelease::Release.new(version: '1.2.3', gemspec_version: '1.2.3', date: Date.today) }
  let(:registry) { {} }
  let(:paths) { [] }
  let(:collection) do
    members = paths.map do |path|
      spec = Gem::Package.new(path).spec
      RubyGemRelease::Package::Prebuilt.new(path: path, sha256: Digest::SHA256.file(path).hexdigest,
                                            name: spec.name, version: spec.version.to_s, platform: spec.platform.to_s)
    end
    RubyGemRelease::Package::Collection.new(packages: members)
  end

  around do |example|
    Dir.chdir(directory) { example.run }
  ensure
    FileUtils.remove_entry(directory)
  end

  before do
    File.write('version.rb', "VERSION = '1.2.3'\n")
    %w[ruby java].each do |platform|
      File.write('fixture.gemspec', <<~RUBY)
        Gem::Specification.new do |spec|
          spec.name = 'release-fixture'
          spec.version = '1.2.3'
          spec.platform = '#{platform}'
          spec.summary = 'Release fixture'
          spec.authors = ['Fixture']
          spec.files = ['version.rb']
        end
      RUBY
      paths << RubyGemRelease::Package::RubyGem.new(gemspec: 'fixture.gemspec', directory: File.join(directory, platform)).build!(release)
    end
    http = instance_double(Net::HTTP)
    allow(Net::HTTP).to receive(:start).and_yield(http)
    allow(http).to receive(:get) do |uri|
      platform = URI.decode_www_form(URI(uri).query).to_h.fetch('platform')
      checksum = registry[platform]
      instance_double(Net::HTTPResponse, code: checksum ? '200' : '404', body: JSON.generate('sha' => checksum))
    end
    allow(Open3).to receive(:capture3).with(Gem.ruby, '-S', 'gem', 'push', anything) do |*arguments|
      path = arguments.last
      registry[Gem::Package.new(path).spec.platform.to_s] = Digest::SHA256.file(path).hexdigest
      ['published', '', instance_double(Process::Status, success?: true)]
    end
  end

  it 'publishes exactly both retained archives once without consulting or rebuilding the source' do
    collection.build!(release)
    File.write('fixture.gemspec', "raise 'No rebuild allowed'\n")
    2.times { described_class.new.publish!(release, package: collection) }
    paths.each { |path| expect(Open3).to have_received(:capture3).with(Gem.ruby, '-S', 'gem', 'push', path).once }
    expect(described_class.new.published?(release, package: collection)).to be(true)
  end

  it 'checks every local archive before any registry request or upload' do
    collection
    File.write(paths.last, 'changed')
    expect { described_class.new.publish!(release, package: collection) }.to raise_error(/Prebuilt artifact changed/)
    expect(Net::HTTP).not_to have_received(:start)
    expect(Open3).not_to have_received(:capture3).with(Gem.ruby, '-S', 'gem', 'push', anything)
  end

  it 'checks later registry members before uploading an earlier missing member' do
    registry['java'] = '0' * 64
    expect { described_class.new.publish!(release, package: collection) }.to raise_error(/checksum differs/)
    expect(Open3).not_to have_received(:capture3).with(Gem.ruby, '-S', 'gem', 'push', anything)
  end

  it 'resumes partial publication and accepts a response lost after successful publication' do
    allow(Open3).to receive(:capture3).with(Gem.ruby, '-S', 'gem', 'push', paths.first) do
      registry['ruby'] = Digest::SHA256.file(paths.first).hexdigest
      ['', 'Response lost', instance_double(Process::Status, success?: false)]
    end
    allow(Open3).to receive(:capture3).with(Gem.ruby, '-S', 'gem', 'push', paths.last)
                                      .and_return(['', 'Rejected', instance_double(Process::Status, success?: false)],
                                                  ['published', '', instance_double(Process::Status, success?: true)])
    expect { described_class.new.publish!(release, package: collection) }.to raise_error(/Rejected/)
    expect { described_class.new.publish!(release, package: collection) }.not_to raise_error
    expect(Open3).to have_received(:capture3).with(Gem.ruby, '-S', 'gem', 'push', paths.first).once
    expect(Open3).to have_received(:capture3).with(Gem.ruby, '-S', 'gem', 'push', paths.last).twice
  end

  it 'rejects duplicate identities and conflicting expected metadata' do
    duplicate = RubyGemRelease::Package::Collection.new(packages: [collection.packages.first] * 2)
    expect { duplicate.artifacts(release) }.to raise_error(/Duplicate package identities/)
    wrong = RubyGemRelease::Package::Prebuilt.new(path: paths.first, sha256: Digest::SHA256.file(paths.first).hexdigest, name: 'other', version: '1.2.3')
    expect { wrong.artifact(release) }.to raise_error(/identity differs/)
    expect { wrong.artifact(release.with_version('2.0.0')) }.to raise_error(/version does not match/)
  end
end
