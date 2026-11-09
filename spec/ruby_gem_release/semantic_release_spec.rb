# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/semantic_release'

RSpec.describe RubyGemRelease::SemanticRelease do
  let(:commits) { [{ 'sha' => 'b' * 40, 'message' => "feat(api)!: Replace endpoint\n\nBREAKING CHANGE: Old endpoint removed.".dup }] }
  let(:last_release) { { 'tag' => 'v1.2.3', 'version' => '1.2.3', 'commit' => 'c' * 40 } }
  let(:history) { instance_double(described_class::GitHistory, read: { last_release: last_release, commits: commits }) }

  it 'composes history, analysis, selection, and notes into an immutable serializable decision' do
    decision = described_class.new(history: history).analyze(head: 'a' * 40)
    expect(decision).to have_attributes(version: '2.0.0', release_type: 'major', last_release: last_release, commits: commits, explicit_version: nil)
    expect(decision.notes).to include('### Breaking Changes', 'Old endpoint removed.', '### Features', '**api:** Replace endpoint', 'bbbbbbb')
    expect(decision).to be_frozen
    expect { decision.commits.first['message'].replace('changed') }.to raise_error(FrozenError)
    expect { decision.last_release['version'] = '9.0.0' }.to raise_error(FrozenError)
    expect { decision.notes << 'changed' }.to raise_error(FrozenError)
    expect(described_class::Decision.from_h(JSON.parse(JSON.generate(decision.to_h))).to_h).to eq(decision.to_h)
    commits.first['message'].replace('changed')
    expect(decision.commits.first.fetch('message')).to start_with('feat')
  end

  it 'persists a no-release decision without inventing notes or a version' do
    commits.first['message'] = 'docs: Explain usage'
    decision = described_class.new(history: history).analyze(head: 'a' * 40)
    expect(decision).to have_attributes(version: nil, notes: nil, release_type: nil)
    expect(decision).not_to be_release
    expect(decision.commits).to eq(commits)
  end

  it 'selects the first release independently of the analyzed severity' do
    allow(history).to receive(:read).and_return(last_release: nil, commits: commits)
    decision = described_class.new(history: history).analyze(head: 'a' * 40)
    expect(decision).to have_attributes(version: '1.0.0', release_type: 'major', last_release: nil)
  end

  it 'supports independent analyzer, version selector, and note providers' do
    analyzer = instance_double(described_class::ConventionalCommits, analyze: 'patch')
    selector = instance_double(described_class::VersionSelector, select: '1.2.4')
    notes = instance_double(described_class::ReleaseNotes, generate: 'Custom notes.')
    decision = described_class.new(history: history, analyzer: analyzer, selector: selector, notes: notes).analyze(head: 'a' * 40)
    expect(decision).to have_attributes(version: '1.2.4', notes: 'Custom notes.')
    expect(analyzer).to have_received(:analyze).with(commits).once
    expect(selector).to have_received(:select).with(last_release: '1.2.3', release_type: 'patch', explicit_version: nil)
    expect(notes).to have_received(:generate).with(commits: commits, version: '1.2.4', last_release: last_release)
  end

  it 'forces an explicit release without commits and binds the decision to its inputs' do
    allow(history).to receive(:read).and_return(last_release: last_release, commits: [])
    decision = described_class.new(history: history).analyze(head: 'a' * 40, explicit_version: '1.3.0')
    expect(decision).to have_attributes(version: '1.3.0', release_type: nil, notes: 'Explicit version release.')
    decision.check!(head: 'a' * 40, explicit_version: '1.3.0', version: '1.3.0')
    expect { decision.check!(head: 'b' * 40, explicit_version: '1.3.0') }.to raise_error(ArgumentError, /another commit/)
    expect { decision.check!(head: 'a' * 40, explicit_version: '') }.to raise_error(ArgumentError, /explicit version changed/)
    expect { decision.check!(head: 'a' * 40, explicit_version: '1.3.0', version: '1.3.1') }.to raise_error(ArgumentError, /differs/)
  end

  it 'rejects invalid serialized decisions rather than using partial or unsupported data' do
    attributes = described_class.new(history: history).analyze(head: 'a' * 40).to_h
    invalid = [
      attributes.merge('extra' => nil), attributes.except('commits'), attributes.merge('head' => 'HEAD'),
      attributes.merge('commits' => [{}]), attributes.merge('commits' => commits * 2),
      attributes.merge('last_release' => false), attributes.merge('release_type' => 'prerelease'),
      attributes.merge('version' => '1.0.0'), attributes.merge('version' => nil),
      attributes.merge('notes' => ''), attributes.merge('explicit_version' => '3.0.0')
    ]
    invalid.each { |value| expect { described_class::Decision.from_h(value) }.to raise_error(ArgumentError) }
  end

  it 'excludes canceled commits from notes and escapes Markdown syntax in commit headers' do
    original = { 'sha' => 'b' * 40, 'message' => 'feat: Removed' }
    revert = { 'sha' => 'c' * 40, 'message' => "Revert feature\n\nThis reverts commit #{'b' * 40}." }
    fix = { 'sha' => 'd' * 40, 'message' => 'fix(core): Handle <input> and *stars*' }
    notes = described_class::ReleaseNotes.new.generate(commits: [original, revert, fix], version: '1.2.4', last_release: last_release)
    expect(notes).to include('### Bug Fixes', '**core:** Handle \\<input\\> and \\*stars\\*')
    expect(notes).not_to include('Removed', 'Revert feature')
  end
end
