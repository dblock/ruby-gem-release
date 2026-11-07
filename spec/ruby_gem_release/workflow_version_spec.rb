# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'open3'
require 'tmpdir'

RSpec.describe 'Workflow version resolution' do # rubocop:disable RSpec/DescribeClass -- Test executable workflow steps rather than a Ruby class.
  let(:directory) { Dir.mktmpdir }
  let(:environment_file) { File.join(directory, 'environment') }
  let(:workflow) { YAML.load_file('.github/workflows/release.yml') }
  let(:environment) do
    {
      'BUNDLE_GEMFILE' => File.expand_path('Gemfile'),
      'GEMSPEC' => File.join(directory, 'fixture.gemspec'),
      'GITHUB_ENV' => environment_file,
      'INPUT_VERSION' => ''
    }
  end

  before do
    File.write(File.join(directory, 'fixture.gemspec'), "require_relative 'version'\nGem::Specification.new { |spec| spec.version = VERSION }\n")
    File.write(File.join(directory, 'version.rb'), "VERSION = '1.2.3'\n")
    File.write(environment_file, '')
    system('git', 'init', '--quiet', directory, exception: true)
  end

  after { FileUtils.remove_entry(directory) }

  def run_step(name, overrides = {})
    script = workflow.fetch('jobs').fetch('release').fetch('steps').find { |step| step['name'] == name }.fetch('run')
    Open3.capture3(environment.merge(overrides), 'bash', '-c', script, chdir: directory)
  end

  it 'retains the initial version while resolving the prepared version', :aggregate_failures do
    expect(run_step('Capture Release Context').last).to be_success
    File.write(File.join(directory, 'version.rb'), "VERSION = '2.0.0'\n")
    expect(run_step('Resolve Prepared Version').last).to be_success
    expect(File.read(environment_file)).to include("RELEASE_PREVIOUS_VERSION=1.2.3\n", "RELEASE_VERSION=2.0.0\n")
  end

  it 'rejects an expected-version mismatch before recording a release', :aggregate_failures do
    output, _error, status = run_step('Resolve Prepared Version', 'INPUT_VERSION' => '2.0.0')
    expect(status).not_to be_success
    expect(output).to include('does not match expected version')
    expect(File.read(environment_file)).to eq('')
  end

  it 'rejects a gemspec that cannot be loaded', :aggregate_failures do
    _output, error, status = run_step('Resolve Prepared Version', 'GEMSPEC' => File.join(directory, 'missing.gemspec'))
    expect(status).not_to be_success
    expect(error).to include('Cannot load gemspec')
    expect(File.read(environment_file)).to eq('')
  end
end
