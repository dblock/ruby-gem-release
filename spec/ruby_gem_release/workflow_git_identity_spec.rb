# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'open3'
require 'tmpdir'

RSpec.describe 'Workflow Git identity' do # rubocop:disable RSpec/DescribeClass -- Execute workflow configuration.
  let(:directory) { Dir.mktmpdir }
  let(:workflow) { YAML.load_file('.github/workflows/release.yml') }
  let(:environment) do
    {
      'DRY_RUN' => 'true', 'INPUT_GEMSPEC' => 'fixture.gemspec', 'GITHUB_ENV' => File.join(directory, 'environment'),
      'GITHUB_OUTPUT' => File.join(directory, 'output'), 'DEFAULT_BRANCH' => 'master',
      'GIT_USER_NAME' => 'Release Maintainer', 'GIT_USER_EMAIL' => 'release@example.com'
    }
  end

  before do
    File.write(File.join(directory, 'fixture.gemspec'), '')
    system('git', 'init', '--quiet', directory, exception: true)
    system('git', '-C', directory, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com',
           'commit', '--quiet', '--allow-empty', '-m', 'Fixture', exception: true)
  end

  after { FileUtils.remove_entry(directory) }

  def run_identity(overrides = {})
    script = workflow.fetch('jobs').fetch('release').fetch('steps').find { |step| step['name'] == 'Check Release Inputs and Branch' }.fetch('run')
    script = script.sub('git fetch origin "$DEFAULT_BRANCH" --tags', ':')
    Open3.capture3(environment.merge(overrides), 'bash', '-euo', 'pipefail', '-c', script, chdir: directory)
  end

  it 'configures the custom identity locally', :aggregate_failures do
    expect(run_identity.last).to be_success
    expect(Open3.capture2('git', 'config', '--local', 'user.name', chdir: directory).first.strip).to eq('Release Maintainer')
    expect(Open3.capture2('git', 'config', '--local', 'user.email', chdir: directory).first.strip).to eq('release@example.com')
  end

  it 'retains bot defaults', :aggregate_failures do
    inputs = workflow.fetch(true).fetch('workflow_call').fetch('inputs')
    expect(inputs.fetch('git-user-name').fetch('default')).to eq('github-actions[bot]')
    expect(inputs.fetch('git-user-email').fetch('default')).to eq('github-actions[bot]@users.noreply.github.com')
  end

  it 'rejects blank and multiline identity values', :aggregate_failures do
    ['', '   ', "name\nother", "email\rother"].each do |value|
      expect(run_identity('GIT_USER_NAME' => value).last).not_to be_success
      expect(run_identity('GIT_USER_EMAIL' => value).last).not_to be_success
    end
  end
end
