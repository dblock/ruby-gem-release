# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'
require 'rubygems/package'

RSpec.describe 'Provider-neutral release lifecycle' do
  let(:directory) { Dir.mktmpdir }
  let(:checkout) { File.join(directory, 'checkout') }
  let(:remote) { File.join(directory, 'remote.git') }
  let(:environment) do
    ENV.to_h.slice('PATH', 'HOME', 'TMPDIR', 'LANG').merge(
      'BUNDLE_GEMFILE' => ENV.fetch('RELEASE_CONSUMER_GEMFILE', File.expand_path('Gemfile')),
      'RUBYLIB' => ENV.fetch('RELEASE_CONSUMER_LIB', File.expand_path('lib')),
      'RELEASE_TEST_LIB' => ENV.fetch('RELEASE_CONSUMER_LIB', File.expand_path('lib')),
      'GEM_HOME' => ENV.fetch('RELEASE_CONSUMER_GEM_HOME', Gem.dir),
      'GEM_PATH' => ENV.fetch('RELEASE_CONSUMER_GEM_PATH', Gem.path.join(File::PATH_SEPARATOR)),
      'GIT_CONFIG_NOSYSTEM' => '1', 'GIT_CONFIG_GLOBAL' => File::NULL,
      'RELEASE_DIRECTORY' => File.join(directory, 'artifacts'),
      'CONSUMER_ENVIRONMENT' => File.join(directory, 'environment.json'),
      'CONSUMER_OUTPUT' => File.join(directory, 'output.json'),
      'RELEASE_REF' => 'refs/heads/master', 'DEFAULT_BRANCH' => 'master',
      'INPUT_VERSION' => '0.2.0', 'INPUT_GEMSPEC' => 'example.gemspec',
      'RELEASE_TEST_REMOTE' => remote, 'TZ' => 'UTC'
    )
  end

  before do
    FileUtils.mkdir_p(File.join(checkout, 'lib/example'))
    FileUtils.mkdir_p(environment.fetch('RELEASE_DIRECTORY'))
    File.write(File.join(checkout, 'lib/example/version.rb'), "module Example\n  VERSION = '0.1.0'\nend\n")
    File.write(File.join(checkout, 'example.gemspec'), <<~RUBY)
      require_relative 'lib/example/version'
      Gem::Specification.new do |spec|
        spec.name = 'example'
        spec.version = Example::VERSION
        spec.authors = ['Fixture']
        spec.summary = 'Portable release fixture'
        spec.files = ['lib/example/version.rb']
      end
    RUBY
    File.write(File.join(checkout, 'CHANGELOG.md'), "# Changelog\n\n## [Unreleased]\n\n- Change.\n")
    FileUtils.cp('spec/fixtures/portable_consumer.rb', File.join(checkout, 'Rakefile'))
    run_git('init', '--bare', '--quiet', '-b', 'master', remote)
    run_git('init', '--quiet', '-b', 'master', checkout)
    run_git('-C', checkout, 'add', '.')
    run_git('-C', checkout, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'commit', '--quiet', '-m', 'Initial')
    run_git('-C', checkout, 'remote', 'add', 'origin', remote)
    run_git('-C', checkout, 'push', '--quiet', '-u', 'origin', 'master')
  end

  after { FileUtils.remove_entry(directory) }

  def run_git(*arguments)
    output, error, status = Open3.capture3('git', *arguments)
    raise error unless status.success?

    output.strip
  end

  def run_task(name)
    output, error, status = Open3.capture3(environment, 'bundle', 'exec', 'rake', name, chdir: checkout, unsetenv_others: true)
    path = environment.fetch('CONSUMER_ENVIRONMENT')
    environment.merge!(JSON.parse(File.read(path))) if File.exist?(path)
    return if status.success?

    environment['CONSUMER_FAILURES'] = JSON.generate([name])
    raise "#{output}\n#{error}"
  end

  def prepare_release
    run_task('release:workflow:capture')
    run_task('release:validate')
    expect(JSON.parse(File.read(environment.fetch('CONSUMER_OUTPUT')))).to eq('proceed' => 'true')
    %w[release:prepare release:workflow:resolve test].each { |name| run_task(name) }
  end

  def artifact(name)
    File.join(environment.fetch('RELEASE_DIRECTORY'), name)
  end

  def events
    File.readlines(artifact('events.jsonl')).map { |line| JSON.parse(line) }
  end

  it 'publishes and bumps across independent processes without an Actions environment' do
    prepare_release
    expect(environment.fetch('RELEASE_AUTHENTICATION')).to eq('')
    expect(File.stat(environment.fetch('RELEASE_STATE')).mode & 0o777).to eq(0o600)
    run_task('release:publish')
    release_commit = run_git('--git-dir', remote, 'rev-parse', 'v0.2.0')
    expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(release_commit)
    expect(run_git('--git-dir', remote, 'show', 'v0.2.0:lib/example/version.rb')).to include("VERSION = '0.2.0'")
    expect(run_git('--git-dir', remote, 'log', '-1', '--format=%an <%ae>')).to eq('ruby-gem-release <ruby-gem-release@localhost>')
    run_task('release:bump')
    run_task('release:success')
    expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(run_git('-C', checkout, 'rev-parse', 'HEAD'))
    expect(run_git('--git-dir', remote, 'rev-parse', 'v0.2.0')).to eq(release_commit)
    expect(run_git('--git-dir', remote, 'show', 'master:lib/example/version.rb')).to include("VERSION = '0.2.1'")
    expect(run_git('-C', checkout, 'status', '--porcelain')).to eq('')
    expect(File.read(File.join(checkout, 'CHANGELOG.md'))).to include('## [Unreleased]', '## [0.2.0] -')
    publications = events.select { |event| %w[publish hosting].include?(event.fetch('event')) }
    digest = JSON.parse(File.read(artifact('release.json'))).fetch('sha256')
    expect(publications.map { |event| event.values_at('event', 'tags', 'sha256') }).to eq([['publish', [], digest], ['hosting', ['v0.2.0'], digest]])
    expect(publications.map { |event| event.fetch('path') }).to eq([artifact('example-0.2.0.gem')] * 2)
    expect(File.binread(artifact('example-0.2.0.gem'))).to eq(File.binread(artifact('release.gem')))
    expect(Gem::Package.new(artifact('release.gem')).spec.version.to_s).to eq('0.2.0')
    expect(File).to exist(artifact('release.bundle'))
    success = events.find { |event| event['event'] == 'success' }
    expect(success).to include('version' => '0.2.0', 'previous_version' => '0.1.0', 'next_version' => '0.2.1',
                               'context_class' => 'RubyGemRelease::ExecutionContext', 'step' => 'release:success',
                               'provider' => 'PortableConsumer::Provider', 'run' => nil, 'steps' => {})
    invocations = events.select { |event| event['event'] == 'invocation' }
    expect(invocations.map { |event| event.fetch('task') }).to eq(%w[release:workflow:capture release:validate release:prepare release:workflow:resolve test release:publish release:bump release:success])
    expect(invocations.map { |event| event.fetch('pid') }.uniq.size).to eq(invocations.size)
  end

  it 'delivers captured errors across processes and preserves recovery files without pushing a rejected release' do
    initial = run_git('--git-dir', remote, 'rev-parse', 'master')
    prepare_release
    environment['CONSUMER_FAIL_PUBLICATION'] = 'true'
    expect { run_task('release:publish') }.to raise_error(/Registry rejected release/)
    run_task('release:workflow:failure_phase')
    run_task('release:failure')
    expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(initial)
    expect(run_git('--git-dir', remote, 'tag')).to eq('')
    %w[release.gem release.json release.bundle].each { |name| expect(File).to exist(artifact(name)) }
    failure = events.find { |event| event['event'] == 'failure' }
    expect(failure).to include('phase' => 'release:publish', 'step' => 'release:failure', 'error' => 'Registry rejected release',
                               'version' => '0.2.0', 'next_version' => nil, 'context_class' => 'RubyGemRelease::ExecutionContext',
                               'provider' => 'PortableConsumer::Provider')
    expect(events.map { |event| event.fetch('event') }).not_to include('hosting', 'success')
  end
end
