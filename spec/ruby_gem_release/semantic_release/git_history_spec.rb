# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/semantic_release'
require 'tmpdir'

RSpec.describe RubyGemRelease::SemanticRelease::GitHistory do
  around do |example|
    Dir.mktmpdir do |directory|
      Dir.chdir(directory) do
        git('init', '--quiet', '-b', 'master')
        git('config', 'user.name', 'Fixture')
        git('config', 'user.email', 'fixture@example.com')
        example.run
      end
    end
  end

  def git(*arguments)
    output, error, status = Open3.capture3('git', *arguments)
    raise error unless status.success?

    output.strip
  end

  def commit(message)
    git('commit', '--quiet', '--allow-empty', '-m', message)
    git('rev-parse', 'HEAD')
  end

  it 'returns all reachable commits for the first release, preserving complete messages' do
    first = commit("feat: First change\n\nBody with Unicode: café.")
    head = commit('fix: Second change')
    history = described_class.new.read(head: head)
    expect(history[:last_release]).to be_nil
    expect(history[:commits].map { |entry| entry.fetch('sha') }).to eq([first, head])
    expect(history[:commits].first.fetch('message')).to eq("feat: First change\n\nBody with Unicode: café.\n")
  end

  it 'uses the highest reachable stable tag, not the nearest tag, and ignores tags on unrelated branches' do
    released = commit('feat: Released')
    git('tag', '-a', 'v2.0.0', '-m', 'Release')
    git('checkout', '--quiet', '-b', 'other')
    commit('feat!: Unrelated')
    git('tag', 'v99.0.0')
    git('checkout', '--quiet', 'master')
    subsequent = commit('fix: Repair')
    %w[v1.9.9 v9.0.0-beta.1 unrelated v8.0.0+build].each { |tag| git('tag', tag) }
    head = commit('docs: Explain')
    history = described_class.new.read(head: head)
    expect(history[:last_release]).to eq('tag' => 'v2.0.0', 'version' => '2.0.0', 'commit' => released)
    expect(history[:commits].map { |entry| entry.fetch('sha') }).to eq([subsequent, head])
  end

  it 'rejects stale captured heads and shallow checkouts instead of guessing the release baseline' do
    previous = commit('feat: First')
    head = commit('fix: Second')
    expect { described_class.new.read(head: previous) }.to raise_error(ArgumentError, /checkout changed/)
    expect { described_class.new.read(head: 'HEAD') }.to raise_error(ArgumentError, /captured commit SHA/)
    git('clone', '--quiet', '--depth=1', "file://#{Dir.pwd}", 'shallow')
    Dir.chdir('shallow') do
      expect { described_class.new.read(head: head) }.to raise_error(ArgumentError, /complete checkout/)
    end
  end

  it 'reports Git failures' do
    commit('feat: First')
    git('config', '--local', 'core.repositoryformatversion', '999')
    expect { described_class.new.read(head: 'a' * 40) }.to raise_error(/Semantic history Git command failed/)
  end
end
