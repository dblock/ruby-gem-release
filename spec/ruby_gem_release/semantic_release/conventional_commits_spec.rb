# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/semantic_release'

RSpec.describe RubyGemRelease::SemanticRelease::ConventionalCommits do
  def commits(*messages)
    messages.each_with_index.map { |message, index| { 'sha' => (index + 1).to_s(16).rjust(40, '0'), 'message' => message } }
  end

  it 'selects the highest Conventional Commits release type' do
    {
      'feat(api)!: Replace API' => 'major',
      "refactor: Replace API\n\nBREAKING CHANGE: Removed the old API\nUse the new API." => 'major',
      "fix: Replace API\n\nBREAKING-CHANGE: Removed the old API" => 'major',
      'feat(api): Add endpoint' => 'minor',
      'fix: Repair endpoint' => 'patch',
      'perf: Reduce allocations' => 'patch',
      'docs: Explain API' => nil,
      'chore: Update tooling' => nil,
      'Unstructured message' => nil,
      '' => nil
    }.each do |message, type|
      expect(described_class.new.analyze(commits(message))).to eq(type), message.inspect
    end
    expect(described_class.new.analyze(commits('fix: Repair', 'feat: Add', 'chore!: Remove'))).to eq('major')
  end

  it 'lets matching custom rules override defaults, using the highest match and falling back for unmatched commits' do
    analyzer = described_class.new(rules: [
                                     { scope: 'no-release', release: false },
                                     { type: 'docs', scope: 'api*', release: :minor },
                                     { type: 'docs', release: :patch }
                                   ])
    expect(analyzer.analyze(commits('feat(no-release)!: Ignore this'))).to be_nil
    expect(analyzer.analyze(commits('docs(api-v2): Explain API'))).to eq('minor')
    expect(analyzer.analyze(commits('docs: Explain usage'))).to eq('patch')
    expect(analyzer.analyze(commits('feat: Add endpoint'))).to eq('minor')
    expect(analyzer.analyze(commits('feat(no-release): Ignore', 'fix: Repair'))).to eq('patch')
  end

  it 'matches breaking, revert, and subject selectors and rejects unsupported rules' do
    analyzer = described_class.new(rules: [{ breaking: true, subject: 'Internal*', release: false }, { revert: true, release: false }])
    expect(analyzer.analyze(commits('fix!: Internal change'))).to be_nil
    expect(analyzer.analyze(commits("Revert old change\n\nThis reverts commit #{'a' * 40}."))).to be_nil
    [{ type: 'fix' }, { unknown: '*', release: :minor }, { breaking: '*', release: :major }, { release: :prerelease }, { type: false, release: false }].each do |rule|
      expect { described_class.new(rules: [rule]) }.to raise_error(ArgumentError)
    end
  end

  it 'cancels original and revert pairs, including abbreviated hashes, but releases reverts of older changes' do
    original = { 'sha' => "1234567#{'0' * 33}", 'message' => 'feat: Add endpoint' }
    revert = { 'sha' => 'a' * 40, 'message' => "Revert \"feat: Add endpoint\"\n\nThis reverts commit 1234567." }
    expect(described_class.new.analyze([original, revert])).to be_nil
    expect(described_class.new.analyze([revert])).to eq('patch')
    restored = { 'sha' => 'b' * 40, 'message' => "Revert the revert\n\nThis reverts commit #{revert.fetch('sha')}." }
    expect(described_class.new.analyze([original, revert, restored])).to eq('minor')
  end

  it 'retains multiline breaking notes without swallowing other footers' do
    message = "feat(api)!: Replace API\n\nBREAKING CHANGE: Old endpoint removed.\n\nUse the new endpoint.\nRefs: #42\nNot a breaking note."
    parsed = described_class.new.parsed(commits(message)).first
    expect(parsed).to include(type: 'feat', scope: 'api', subject: 'Replace API', breaking: true, notes: ["Old endpoint removed.\n\nUse the new endpoint."])
    expect(described_class.new.parsed(commits('feat!: Replace API')).first[:notes]).to eq(['Replace API'])
  end
end
