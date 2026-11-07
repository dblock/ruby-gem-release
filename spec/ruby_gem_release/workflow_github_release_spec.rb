# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'open3'
require 'tmpdir'
require 'rubygems/package'

RSpec.describe 'Workflow release lifecycle' do # rubocop:disable RSpec/DescribeClass -- Exercise the documented consumer through workflow commands.
  let(:directory) { Dir.mktmpdir }
  let(:checkout) { File.join(directory, 'checkout') }
  let(:remote) { File.join(directory, 'remote.git') }
  let(:workflow) { YAML.load_file('.github/workflows/release.yml') }
  let(:environment) do
    {
      'BUNDLE_GEMFILE' => File.expand_path('Gemfile'),
      'RUBYLIB' => File.expand_path('lib'),
      'RUNNER_TEMP' => directory,
      'GITHUB_ENV' => File.join(directory, 'environment'),
      'GITHUB_REPOSITORY' => 'owner/example',
      'DEFAULT_BRANCH' => 'master',
      'INPUT_VERSION' => '',
      'INPUT_GEMSPEC' => '',
      'DRY_RUN' => 'true'
    }
  end

  def consumer_rakefile
    File.read('examples/keep_a_changelog/Rakefile')
  end

  before do
    FileUtils.mkdir_p(File.join(checkout, 'lib/example'))
    File.write(File.join(checkout, 'lib/example/version.rb'), "module Example\n  VERSION = '0.1.0'\nend\n")
    File.write(File.join(checkout, 'example.gemspec'), <<~RUBY)
      require_relative 'lib/example/version'
      Gem::Specification.new do |spec|
        spec.name = 'example'
        spec.version = Example::VERSION
        spec.authors = ['Fixture']
        spec.summary = 'Release fixture'
        spec.files = ['lib/example/version.rb']
      end
    RUBY
    FileUtils.cp('examples/keep_a_changelog/CHANGELOG.md', checkout)
    File.write(File.join(checkout, 'Rakefile'), "#{consumer_rakefile}\n#{remote_write_guard}")
    run_git('init', '--bare', '--quiet', '-b', 'master', remote)
    run_git('init', '--quiet', '-b', 'master', checkout)
    run_git('-C', checkout, 'add', '.')
    run_git('-C', checkout, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'commit', '--quiet', '-m', 'Initial')
    run_git('-C', checkout, 'remote', 'add', 'origin', remote)
    run_git('-C', checkout, 'push', '--quiet', '-u', 'origin', 'master')
  end

  after { FileUtils.remove_entry(directory) }

  def remote_write_guard
    <<~RUBY
      module RejectRemoteWrites
        def capture3(*command)
          raise 'Unexpected remote write in dry run' if command.include?('push') || command.first == 'gh'
          super
        end
      end
      Open3.singleton_class.prepend(RejectRemoteWrites)
    RUBY
  end

  def run_git(*arguments)
    output, error, status = Open3.capture3('git', *arguments)
    raise error unless status.success?

    output.strip
  end

  def phase_command(name)
    step = workflow.fetch('jobs').fetch('release').fetch('steps').find { |item| item['name'] == name }
    inputs = workflow.fetch(true).fetch('workflow_call').fetch('inputs')
    command_input = step.dig('env', 'COMMAND')
    command_input ? inputs.fetch(command_input[/inputs\.(\w+)/, 1]).fetch('default') : step.fetch('run')
  end

  def run_phase(name)
    output, error, status = Open3.capture3(environment, 'bash', '-euo', 'pipefail', '-c', phase_command(name), chdir: checkout)
    raise "#{output}\n#{error}" unless status.success?

    File.readlines(environment.fetch('GITHUB_ENV'), chomp: true).each do |line|
      key, value = line.split('=', 2)
      environment[key] = value
    end
  end

  shared_examples 'a local release lifecycle' do
    it 'runs the documented callbacks, preserving the exact artifact without remote writes', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- Exercise separate workflow processes and a real consumer.
      initial = run_git('--git-dir', remote, 'rev-parse', 'master')
      run_phase('Capture Release Context')
      run_phase('Prepare Release')
      run_phase('Resolve Prepared Version')
      run_phase('Publish Release')
      release_commit = run_git('-C', checkout, 'rev-parse', 'HEAD')
      expect(run_git('-C', checkout, 'rev-parse', 'v0.1.0')).to eq(release_commit)
      expect(Gem::Package.new(File.join(directory, 'release.gem')).spec.version.to_s).to eq('0.1.0')
      expect(File).to exist(File.join(directory, 'release.bundle'))
      run_phase('Prepare Next Development Version')
      expect(File.read(File.join(checkout, 'lib/example/version.rb'))).to include("VERSION = '0.1.1'")
      expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(initial)
      expect(run_git('--git-dir', remote, 'tag')).to eq('')
      expect(run_git('-C', checkout, 'status', '--porcelain')).to eq('')
    end
  end

  it_behaves_like 'a local release lifecycle'

  context 'with detailed manual callbacks' do
    def consumer_rakefile
      File.read('docs/usage.md').split('## Custom Callbacks').last[/```ruby\n(.*?)```/m, 1]
    end

    it_behaves_like 'a local release lifecycle'
  end

  it 'invokes publication in dry runs and preserves artifacts after a failed callback', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- Verify failure-aware artifact preservation and the authentication gate.
    steps = workflow.fetch('jobs').fetch('release').fetch('steps')
    publish = steps.find { |item| item['name'] == 'Publish Release' }
    artifacts = steps.find { |item| item['name'] == 'Preserve Release Artifacts' }
    expect(publish).not_to have_key('if')
    expect(artifacts.fetch('if')).to include('always()')
    expect(steps.index(artifacts)).to be > steps.index(publish)
    expect(steps.find { |item| item['name'] == 'Authenticate to RubyGems' }.fetch('if')).to eq("${{ !inputs.dry-run && inputs.rubygems-owner == '' }}")
    expect(steps.find { |item| item['name'] == 'Authenticate Pending Publisher' }.fetch('if')).to eq("${{ !inputs.dry-run && inputs.rubygems-owner != '' }}")
  end
end
