# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/hosting/github_release'
require 'tmpdir'

RSpec.describe RubyGemRelease::Hosting::GitHubRelease do
  let(:publisher) { described_class.new(repository: 'example/gem') }
  let(:release) { RubyGemRelease::Release.new(version: '1.2.3', previous_version: '1.2.3', date: Date.new(2026, 11, 7)) }
  let(:status) { instance_double(Process::Status, success?: true) }
  let(:directory) { Dir.mktmpdir }

  def artifact
    File.join(directory, 'gem with spaces.gem')
  end

  before do
    File.write(artifact, 'gem')
    allow(Open3).to receive(:capture3).and_return(["https://github.com/example/gem/releases/tag/v1.2.3\n", '', status])
    allow(Open3).to receive(:capture3).with('gh', 'api', '--include', anything).and_return(["HTTP/2.0 404 Not Found\n\n{}", '', status])
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
    allow(Open3).to receive(:capture3).with('gh', 'api', '--include', anything).and_return(["HTTP/2.0 404 Not Found\n\n{}", '', status])
    expect { publisher.publish!(release) }.to raise_error(RuntimeError, /release already exists/)
  end

  it 'uses the persisted notes verbatim instead of requesting platform-generated notes and cleans up the private file' do
    semantic = RubyGemRelease::Release.new(version: '1.2.3', previous_version: '1.2.4', date: release.date, notes: "### Features\n\n- Add endpoint.")
    path = nil
    allow(Open3).to receive(:capture3).with('gh', 'release', 'create', any_args) do |*arguments|
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

  context 'with an existing release' do
    let(:metadata) do
      {
        tag_name: 'v1.2.3', name: 'v1.2.3', draft: false, prerelease: false,
        html_url: 'https://github.com/example/gem/releases/tag/v1.2.3',
        assets: [{ name: File.basename(artifact), digest: "sha256:#{Digest::SHA256.file(artifact).hexdigest}" }]
      }
    end

    before do
      allow(Open3).to receive(:capture3).with('gh', 'api', '--include', anything) do
        ["HTTP/2.0 200 OK\r\n\r\n#{JSON.generate(metadata)}", '', status]
      end
    end

    it 'verifies matching assets without creating or uploading again' do
      expect(publisher.published?(release, artifacts: [artifact])).to be(true)
      publisher.publish!(release, artifacts: [artifact])
      expect(Open3).not_to have_received(:capture3).with('gh', 'release', any_args)
    end

    it 'uploads missing assets with replacement enabled for retry-safe publication' do
      metadata[:assets] = []
      expect(publisher.published?(release, artifacts: [artifact])).to be(false)
      publisher.publish!(release, artifacts: [artifact])
      expect(Open3).to have_received(:capture3).with('gh', 'release', 'upload', 'v1.2.3', '--clobber', '--repo', 'example/gem', artifact)
      expect(Open3).not_to have_received(:capture3).with('gh', 'release', 'create', any_args)
    end

    it 'downloads and hashes assets when GitHub does not provide a digest' do
      metadata[:assets] = [{ name: File.basename(artifact), id: 7 }]
      allow(Open3).to receive(:capture3).with('gh', 'api', 'repos/example/gem/releases/assets/7', '--header', 'Accept: application/octet-stream').and_return(['gem', '', status])
      publisher.publish!(release, artifacts: [artifact])
      expect(Open3).not_to have_received(:capture3).with('gh', 'release', any_args)
    end

    it 'replaces differing metadata, explicit notes and assets, then treats matching outputs as complete' do
      metadata[:draft] = true
      semantic = RubyGemRelease::Release.new(version: release.version, previous_version: release.previous_version, date: release.date, notes: 'Expected notes')
      metadata[:body] = 'Other notes'
      metadata[:assets].first[:digest] = "sha256:#{'0' * 64}"
      notes_path = nil
      allow(Open3).to receive(:capture3).with('gh', 'release', 'edit', any_args) do |*arguments|
        notes_path = arguments[arguments.index('--notes-file') + 1]
        expect(File.read(notes_path)).to eq(semantic.notes)
        metadata.merge!(draft: false, body: semantic.notes)
        ['', '', status]
      end
      allow(Open3).to receive(:capture3).with('gh', 'release', 'upload', any_args) do
        metadata[:assets].first[:digest] = "sha256:#{Digest::SHA256.file(artifact).hexdigest}"
        ['', '', status]
      end
      2.times { publisher.publish!(semantic, artifacts: [artifact]) }
      expect(Open3).to have_received(:capture3).with('gh', 'release', 'edit', any_args).once
      expect(Open3).to have_received(:capture3).with('gh', 'release', 'upload', 'v1.2.3', '--clobber', '--repo', 'example/gem', artifact).once
      expect(File).not_to exist(notes_path)
    end

    it 'rejects a conflicting tag rather than editing a different release' do
      metadata[:tag_name] = 'v9.9.9'
      expect { publisher.publish!(release, artifacts: [artifact]) }.to raise_error(/conflicts/)
      expect(Open3).not_to have_received(:capture3).with('gh', 'release', any_args)
    end

    it 'reports failed metadata updates without attempting asset uploads' do
      metadata[:draft] = true
      allow(Open3).to receive(:capture3).with('gh', 'release', 'edit', any_args).and_return(['', 'forbidden', instance_double(Process::Status, success?: false)])
      expect { publisher.publish!(release, artifacts: [artifact]) }.to raise_error(/update failed.*forbidden/)
      expect(Open3).not_to have_received(:capture3).with('gh', 'release', 'upload', any_args)
    end

    it 'fails closed on permission and network errors rather than creating a duplicate' do
      allow(Open3).to receive(:capture3).with('gh', 'api', '--include', anything).and_return(["HTTP/2.0 403 Forbidden\n\n{}", 'Forbidden', status])
      expect { publisher.publish!(release) }.to raise_error(/HTTP 403/)
      allow(Open3).to receive(:capture3).with('gh', 'api', '--include', anything).and_return(['', 'connection reset', instance_double(Process::Status, success?: false)])
      expect { publisher.publish!(release) }.to raise_error(/connection reset/)
      expect(Open3).not_to have_received(:capture3).with('gh', 'release', any_args)
    end

    it 'refuses duplicate assets and failed or unverifiable asset downloads without writing' do
      metadata[:assets] *= 2
      expect { publisher.publish!(release, artifacts: [artifact]) }.to raise_error(/duplicate asset/)
      metadata[:assets] = [{ name: File.basename(artifact) }]
      expect { publisher.publish!(release, artifacts: [artifact]) }.to raise_error(/cannot be verified/)
      metadata[:assets].first[:id] = 7
      allow(Open3).to receive(:capture3).with('gh', 'api', 'repos/example/gem/releases/assets/7', '--header', 'Accept: application/octet-stream').and_return(['', 'connection reset', instance_double(Process::Status, success?: false)])
      expect { publisher.publish!(release, artifacts: [artifact]) }.to raise_error(/download failed/)
      expect(Open3).not_to have_received(:capture3).with('gh', 'release', any_args)
    end
  end
end
