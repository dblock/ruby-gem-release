# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/source_control/git'
require 'tmpdir'

RSpec.describe RubyGemRelease::SourceControl::Git do
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
    git.stage_changes! { File.write('version', 'release files') }
    git.commit!(context)
    git.tag!(context)
  end

  it 'pushes the exact release commit and tag, then only the next commit', :aggregate_failures do
    allow(Open3).to receive(:capture3).and_call_original
    prepare_tag
    release_commit = git.head
    git.push!(release)
    expect(Open3).to have_received(:capture3).with('git', 'push', '--atomic', 'origin', 'HEAD:refs/heads/master', 'refs/tags/v1.2.3')
    expect(command('--git-dir', remote, 'rev-parse', 'master')).to eq(release_commit)
    expect(command('--git-dir', remote, 'rev-parse', 'v1.2.3')).to eq(release_commit)
    expect(File).to exist(File.join(directory, 'release.bundle'))
    git.stage_changes! { File.write('version', '1.2.4') }
    git.commit_next!(release.with_next_version('1.2.4'))
    expect(command('log', '-1', '--format=%s')).to eq('Prepare next development iteration, 1.2.4')
    git.push!
    expect(command('--git-dir', remote, 'rev-parse', 'master')).to eq(git.head)
    expect(command('--git-dir', remote, 'rev-parse', 'v1.2.3')).to eq(release_commit)
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

  it 'rejects a concurrent update before pushing the next development iteration commit' do
    prepare_tag
    git.push!
    git.stage_changes! { File.write('version', '1.2.4') }
    git.commit_next!(release.with_next_version('1.2.4'))
    advance_remote
    expect { git.push! }.to raise_error(/branch advanced/)
  end

  it 'rejects next development iteration callbacks with no changes' do
    expect { git.commit_next!(release.with_next_version('1.2.4')) }.to raise_error(/did not change any files/)
  end

  it 'rejects a missing iteration version before staging or committing', :aggregate_failures do
    File.write('version', '1.2.4')
    expect { git.commit_next!(release) }.to raise_error(ArgumentError, /iteration version is required/)
    expect(git.head).to eq(initial)
    expect(command('diff', '--cached', '--name-only')).to eq('')
  end

  it 'rejects existing staged and unstaged tracked changes at preflight', :aggregate_failures do
    File.write('version', 'unexpected')
    expect { git.check_clean! }.to raise_error(/clean checkout.*\n  .M "version"/)
    command('add', 'version')
    expect { git.check_clean! }.to raise_error(/clean checkout.*\n  M. "version"/)
    expect(git.head).to eq(initial)
  end

  it 'stages only callback edits, including unusual paths, additions, renames, and deletions', :aggregate_failures do
    paths = ['README.md', "line\nbreak", ':glob', '-option']
    git.stage_changes! do
      paths.each { |path| File.write(path, 'custom release edit') }
      command('mv', 'version', 'renamed version')
    end
    git.commit!(release)
    expect(command('ls-tree', '-rz', '--name-only', 'HEAD').split("\0")).to contain_exactly(*paths, 'renamed version')
    git.stage_changes! { File.delete('renamed version') }
    git.commit_next!(release.with_next_version('1.2.4'))
    expect(command('ls-tree', '-rz', '--name-only', 'HEAD').split("\0")).to match_array(paths)
  end

  it 'never stages or commits unrelated late files', :aggregate_failures do
    git.stage_changes! { File.write('version', 'release edit') }
    File.write('unrelated', 'late output')
    expect { git.commit!(release) }.to raise_error(/commit refused.*"unrelated"/m)
    expect(command('diff', '--cached', '--name-only')).to eq('version')
    expect(git.head).to eq(initial)
  end

  it 'rejects unrelated late index changes without disturbing them', :aggregate_failures do
    git.stage_changes! { File.write('version', 'release edit') }
    File.write('unrelated', 'late output')
    command('add', 'unrelated')
    expect { git.commit!(release) }.to raise_error(/commit refused/)
    expect(command('diff', '--cached', '--name-only').lines.map(&:strip)).to contain_exactly('unrelated', 'version')
    expect(git.head).to eq(initial)
  end

  it 'requires preparation staging instead of staging at publication', :aggregate_failures do
    File.write('version', 'release edit')
    expect { git.commit!(release) }.to raise_error(/stage_changes! during preparation/)
    expect(command('diff', '--cached', '--name-only')).to eq('')
    expect(git.head).to eq(initial)
  end

  it 'rejects late modifications to an already prepared tracked file', :aggregate_failures do
    git.stage_changes! { File.write('version', 'release edit') }
    File.write('version', 'late tracked edit')
    expect { git.commit!(release) }.to raise_error(/commit refused/)
    expect(command('show', ':version')).to eq('release edit')
    expect(git.head).to eq(initial)
  end

  it 'commits custom version, changelog, and README preparation across Git instances', :aggregate_failures do
    git.stage_changes! do
      File.write('version', '2.0.0')
      File.write('CHANGELOG.md', 'custom release notes')
      File.write('README.md', 'custom version callback edit')
    end
    described_class.new(branch: 'master', directory: directory).commit!(release)
    expect(command('show', '--format=', '--name-only', 'HEAD').lines.map(&:strip)).to contain_exactly('version', 'CHANGELOG.md', 'README.md')
    expect(command('status', '--porcelain')).to eq('')
  end

  it 'rejects a discarded preparation index even when the checkout is clean' do
    git.stage_changes! { File.write('version', 'release edit') }
    command('restore', '--source=HEAD', '--staged', '--worktree', 'version')
    expect { git.commit!(release) }.to raise_error(/commit refused/)
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
