# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/github_release'
require 'tmpdir'

RSpec.describe RubyGemRelease::GitHubRelease do
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

  it 'does not invoke gh for a dry-run release', :aggregate_failures do
    dry = RubyGemRelease::Release.new(version: '1.2.3', previous_version: '1.2.3', date: Date.today, dry_run: true)
    publisher.publish!(dry, artifacts: [artifact])
    expect(Open3).not_to have_received(:capture3)
    expect(dry.with_version('2.0.0').with_next_version('2.0.1')).to be_dry_run
  end

  it 'attaches the package-owned exact artifact' do
    package = instance_double(RubyGemRelease::Package, artifact: artifact)
    publisher.publish!(release, package: package)
    expect(package).to have_received(:artifact).with(release)
  end

  it 'rejects invalid versions before invoking gh', :aggregate_failures do
    invalid = release.with_version('1.2.03')
    expect { publisher.publish!(invalid) }.to raise_error(ArgumentError, /MAJOR.MINOR.PATCH/)
    expect(Open3).not_to have_received(:capture3)
  end
end
