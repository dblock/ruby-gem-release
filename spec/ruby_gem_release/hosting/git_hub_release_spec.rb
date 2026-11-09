# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/hosting/github_release'
require 'tmpdir'

RSpec.describe RubyGemRelease::Hosting::GitHubRelease do
  let(:publisher) { described_class.new(repository: 'example/gem') }
  let(:release) { RubyGemRelease::Release.new(version: '1.2.3', previous_version: '1.2.3', date: Date.new(2026, 11, 7)) }
  let(:status) { instance_double(Process::Status, success?: true) }
  let(:directory) { Dir.mktmpdir }
  let(:artifact) { File.join(directory, 'gem with spaces.gem') }

  before do
    File.write(artifact, 'gem')
    allow(Open3).to receive(:capture3).and_return(["https://github.com/example/gem/releases/tag/v1.2.3\n", '', status])
  end

  after { FileUtils.remove_entry(directory) }

  it 'creates a release with a verified tag and the supplied artifact', :aggregate_failures do
    expect(publisher.publish!(release, artifacts: [artifact])).to eq('https://github.com/example/gem/releases/tag/v1.2.3')
    expect(Open3).to have_received(:capture3).with(
      'gh', 'release', 'create', 'v1.2.3', '--repo', 'example/gem', '--verify-tag', '--title', 'v1.2.3', '--generate-notes', artifact
    )
  end

  it 'propagates failed creation without retrying or overwriting' do
    allow(Open3).to receive(:capture3).and_return(['', 'release already exists', instance_double(Process::Status, success?: false)])
    expect { publisher.publish!(release) }.to raise_error(RuntimeError, /release already exists/)
  end

  it 'uses the persisted notes verbatim instead of requesting platform-generated notes and cleans up the private file' do
    semantic = RubyGemRelease::Release.new(version: '1.2.3', previous_version: '1.2.4', date: release.date, notes: "### Features\n\n- Add endpoint.")
    path = nil
    allow(Open3).to receive(:capture3) do |*arguments|
      expect(arguments).not_to include('--generate-notes')
      path = arguments[arguments.index('--notes-file') + 1]
      expect(File.read(path)).to eq(semantic.notes)
      expect(File.stat(path).mode & 0o777).to eq(0o600)
      ['', '', status]
    end
    publisher.publish!(semantic)
    expect(File).not_to exist(path)
  end

  it 'rejects empty custom notes before creating a hosted release' do
    semantic = RubyGemRelease::Release.new(version: '1.2.3', previous_version: '1.2.3', date: release.date, notes: ' ')
    expect { publisher.publish!(semantic) }.to raise_error(ArgumentError, /must not be empty/)
    expect(Open3).not_to have_received(:capture3)
  end

  it 'rejects missing artifacts before invoking gh', :aggregate_failures do
    expect { publisher.publish!(release, artifacts: [File.join(directory, 'missing.gem')]) }.to raise_error(ArgumentError, /existing file/)
    expect(Open3).not_to have_received(:capture3)
  end

  it 'rejects artifact paths with GitHub label syntax', :aggregate_failures do
    path = File.join(directory, 'gem#label.gem')
    File.write(path, 'gem')
    expect { publisher.publish!(release, artifacts: [path]) }.to raise_error(ArgumentError, /without #/)
    expect(Open3).not_to have_received(:capture3)
  end

  it 'rejects invalid repository identifiers' do
    expect { described_class.new(repository: '--repo') }.to raise_error(ArgumentError, %r{OWNER/REPO})
  end

  it 'uses gh checkout inference when no repository is configured' do
    original = ENV.delete('GITHUB_REPOSITORY')
    described_class.new.publish!(release)
    expect(Open3).to have_received(:capture3).with('gh', 'release', 'create', 'v1.2.3', '--verify-tag', '--title', 'v1.2.3', '--generate-notes')
  ensure
    ENV['GITHUB_REPOSITORY'] = original if original
  end

  it 'attaches the package-owned exact artifact' do
    package = instance_double(RubyGemRelease::Package::RubyGem, artifact: artifact)
    publisher.publish!(release, package: package)
    expect(package).to have_received(:artifact).with(release)
  end

  it 'rejects invalid versions before invoking gh', :aggregate_failures do
    invalid = release.with_version('1.2.03')
    expect { publisher.publish!(invalid) }.to raise_error(ArgumentError, /MAJOR.MINOR.PATCH/)
    expect(Open3).not_to have_received(:capture3)
  end
end
