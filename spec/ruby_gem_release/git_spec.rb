# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/git'
require 'tmpdir'

RSpec.describe RubyGemRelease::Git do
  let(:directory) { Dir.mktmpdir }
  let(:remote) { File.join(directory, 'remote.git') }
  let(:git) { described_class.new(branch: 'master', directory: directory) }
  let(:release) { RubyGemRelease::Release.new(version: '1.2.3', previous_version: '1.2.3', date: Date.today) }
  let(:initial) { git.head }

  def checkout
    File.join(directory, 'checkout')
  end

  around do |example|
    original = ENV.to_h
    ENV.delete('RELEASE_INITIAL_COMMIT')
    command('init', '--bare', '--quiet', '-b', 'master', remote)
    command('init', '--quiet', '-b', 'master', checkout)
    Dir.chdir(checkout) { example.run }
  ensure
    ENV.replace(original)
    FileUtils.remove_entry(directory)
  end

  before do
    git.configure!(name: 'Fixture', email: 'fixture@example.com')
    File.write('version', '1.2.3')
    command('add', '.')
    command('commit', '--quiet', '-m', 'Initial')
    command('remote', 'add', 'origin', remote)
    command('push', '--quiet', '-u', 'origin', 'master')
    initial
  end

  def command(*arguments)
    output, error, status = Open3.capture3('git', *arguments)
    raise error unless status.success?

    output.strip
  end

  def prepare_tag(context = release)
    File.write('version', 'release files')
    git.commit!(context)
    git.tag!(context)
  end

  it 'pushes the exact release commit and tag, then only the next commit', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- Exercise both local Git push boundaries.
    allow(Open3).to receive(:capture3).and_call_original
    prepare_tag
    release_commit = git.head
    git.push!(release)
    expect(Open3).to have_received(:capture3).with('git', 'push', '--atomic', 'origin', 'HEAD:refs/heads/master', 'refs/tags/v1.2.3')
    expect(command('--git-dir', remote, 'rev-parse', 'master')).to eq(release_commit)
    expect(command('--git-dir', remote, 'rev-parse', 'v1.2.3')).to eq(release_commit)
    expect(File).to exist(File.join(directory, 'release.bundle'))
    File.write('version', '1.2.4')
    git.commit_next!(release)
    git.push!
    expect(command('--git-dir', remote, 'rev-parse', 'master')).to eq(git.head)
    expect(command('--git-dir', remote, 'rev-parse', 'v1.2.3')).to eq(release_commit)
  end

  it 'creates local commits and tags without changing the remote in a dry run', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- Check both local and remote state.
    dry = RubyGemRelease::Release.new(version: '1.2.3', previous_version: '1.2.3', date: Date.today, dry_run: true)
    prepare_tag(dry)
    git.push!
    expect(command('rev-parse', 'v1.2.3')).to eq(git.head)
    expect(command('--git-dir', remote, 'rev-parse', 'master')).to eq(initial)
    expect(command('--git-dir', remote, 'tag')).to eq('')
  end

  it 'rejects build mutations before creating a tag' do
    git.commit!(release)
    File.write('generated', 'unexpected build mutation')
    expect { git.tag!(release) }.to raise_error(/build changed the working tree/)
  end

  it 'rejects a concurrently advanced remote before tagging' do
    git.commit!(release)
    advance_remote
    expect { git.tag!(release) }.to raise_error(/branch advanced/)
  end

  it 'rejects a concurrently advanced remote after tagging and before pushing' do
    prepare_tag
    advance_remote
    expect { git.push! }.to raise_error(/branch advanced/)
  end

  it 'rejects existing tags without overwriting them' do
    prepare_tag
    expect { git.tag!(release) }.to raise_error(/tag already exists/)
  end

  it 'rejects a concurrent update before pushing the next development commit' do # rubocop:disable RSpec/ExampleLength -- Publish locally before exercising the next-commit concurrency check.
    prepare_tag
    git.push!
    File.write('version', '1.2.4')
    git.commit_next!(release)
    advance_remote
    expect { git.push! }.to raise_error(/branch advanced/)
  end

  it 'rejects next-version callbacks with no changes' do
    expect { git.commit_next!(release) }.to raise_error(/did not change any files/)
  end

  def advance_remote
    other = File.join(directory, 'other')
    command('clone', '--quiet', remote, other)
    Dir.chdir(other) do
      command('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'commit', '--quiet', '--allow-empty', '-m', 'Concurrent')
      command('push', '--quiet')
    end
  end
end
