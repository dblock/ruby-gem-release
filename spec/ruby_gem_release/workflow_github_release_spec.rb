# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'open3'
require 'tmpdir'
require 'json'

RSpec.describe 'Workflow GitHub Release creation' do # rubocop:disable RSpec/DescribeClass -- Execute a workflow command rather than a Ruby class.
  let(:directory) { Dir.mktmpdir }
  let(:workflow) { YAML.load_file('.github/workflows/release.yml') }
  let(:command) { workflow.fetch(true).fetch('workflow_call').fetch('inputs').fetch('github-release').fetch('default') }
  let(:environment) do
    {
      'BUNDLE_GEMFILE' => File.expand_path('Gemfile'),
      'PATH' => "#{directory}#{File::PATH_SEPARATOR}#{ENV.fetch('PATH')}",
      'RUNNER_TEMP' => directory,
      'GITHUB_REPOSITORY' => 'example/gem',
      'GEM_NAME' => 'example',
      'RELEASE_VERSION' => '1.2.3',
      'RELEASE_PREVIOUS_VERSION' => '1.2.0',
      'RELEASE_DATE' => '2026-11-07',
      'GH_TOKEN' => 'test-only-token'
    }
  end

  before do
    File.write(File.join(directory, 'release.gem'), 'exact published artifact')
    File.write(File.join(directory, 'gh'), <<~RUBY)
      #!#{Gem.ruby}
      require 'json'
      File.write(File.join(ENV.fetch('RUNNER_TEMP'), 'arguments.json'), JSON.generate(ARGV))
      puts 'https://github.com/example/gem/releases/tag/v1.2.3'
    RUBY
    File.chmod(0o755, File.join(directory, 'gh'))
  end

  after { FileUtils.remove_entry(directory) }

  it 'runs the default command with the exact artifact and verified tag', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- Verify the full command boundary and artifact.
    output, error, status = Open3.capture3(environment, 'bash', '-euo', 'pipefail', '-c', command)
    artifact = File.join(directory, 'example-1.2.3.gem')
    expect(status.success?).to be(true), error
    expect(output).to include('https://github.com/example/gem/releases/tag/v1.2.3')
    expect(File.read(artifact)).to eq(File.read(File.join(directory, 'release.gem')))
    expect(JSON.parse(File.read(File.join(directory, 'arguments.json'))))
      .to eq(['release', 'create', 'v1.2.3', '--repo', 'example/gem', '--verify-tag', '--title', 'v1.2.3', '--generate-notes', artifact])
  end

  it 'keeps creation after the tag push and before next-version preparation', :aggregate_failures do
    names = workflow.fetch('jobs').fetch('release').fetch('steps').map { |step| step['name'] }
    expect(names.index('Create GitHub Release')).to be > names.index('Push Release Commit and Tag Atomically')
    expect(names.index('Create GitHub Release')).to be < names.index('Prepare Next Development Version')
  end

  it 'gates the entire configurable command in dry-run mode', :aggregate_failures do
    step = workflow.fetch('jobs').fetch('release').fetch('steps').find { |item| item['name'] == 'Create GitHub Release' }
    expect(step.fetch('if')).to eq('${{ !inputs.dry-run }}')
    expect(step.fetch('env').fetch('COMMAND')).to eq('${{ inputs.github-release }}')
  end
end
