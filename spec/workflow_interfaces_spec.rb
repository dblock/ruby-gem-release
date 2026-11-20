# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'open3'
require 'tmpdir'

RSpec.describe 'Release interface contracts' do
  shared_examples 'a release interface' do
    it 'captures after setup, validates before edits, and uses normal failure gating downstream' do
      setup = steps.index { |step| step['uses'] == 'ruby/setup-ruby@v1' }
      capture = steps.index { |step| step['id'] == 'capture_release_context' }
      validation = steps.index { |step| step['id'] == 'validate_release' }
      expect(capture).to be > setup
      expect(validation).to be > capture
      %w[prepare_release resolve_prepared_version test_release checkpoint_release publish_release
         preserve_release_artifacts prepare_next_development_iteration release_success_callback].each do |id|
        step = steps.find { |item| item['id'] == id }
        expect(steps.index(step)).to be > validation
        expect(step.fetch('if', '${{ success() }}')).to eq('${{ success() }}')
      end
    end

    it 'transports enclosing step identities and observed history to configurable commands' do
      steps.select { |step| step.dig('env', 'RELEASE_COMMAND') }.each do |step|
        expect(step.dig('env', 'RELEASE_STEP_ID')).to eq(step.fetch('id'))
        expect(step.dig('env', 'RELEASE_STEPS_JSON')).to eq('${{ toJSON(steps) }}')
      end
    end

    it 'prepares explicitly selected input artifacts before capture and preserves additional paths before publication' do
      preparation = steps.find { |step| step['id'] == 'prepare_input_artifacts' }
      expect(steps.index(preparation)).to be < steps.index { |step| step['id'] == 'capture_release_context' }
      first_task = steps.index { |step| %w[configure_release_inputs capture_release_context].include?(step['id']) }
      expect(steps.index(preparation)).to be < first_task
      expect(preparation.fetch('if')).to eq("${{ inputs.prepare-artifacts != '' }}")
      expect(preparation.dig('env', 'RELEASE_COMMAND')).to eq('${{ inputs.prepare-artifacts }}')
      preservation = steps.find { |step| step['id'] == 'preserve_release_artifacts' }
      expect(preservation.dig('with', 'path')).to include('${{ inputs.artifacts }}', '${{ runner.temp }}/release.bundle')
    end

    it 'requires artifacts before publication and handles failures after Ruby setup' do
      artifacts = steps.find { |step| step['id'] == 'preserve_release_artifacts' }
      expect(artifacts.fetch('if', '')).not_to include('always()')
      expect(artifacts.dig('with', 'if-no-files-found')).to eq('error')
      expect(steps.index(artifacts)).to be > steps.index { |step| step['id'] == 'checkpoint_release' }
      expect(steps.index(artifacts)).to be < steps.index { |step| step['id'] == 'publish_release' }
      phase = steps.find { |step| step['id'] == 'determine_release_failure_phase' }
      failure = steps.find { |step| step['id'] == 'release_failure_callback' }
      expect(phase.dig('env', 'RELEASE_STEPS_JSON')).to eq('${{ toJSON(steps) }}')
      expect(phase.fetch('run')).to eq('bundle exec rake release:workflow:failure_phase')
      expect(steps.index(phase)).to be < steps.index(failure)
      expect(failure.fetch('if')).to include("failure() && steps.setup_ruby.outcome == 'success'")
      expect(failure.dig('env', 'RELEASE_FAILED_STEP_ID')).to be_nil
      success = steps.find { |step| step['id'] == 'release_success_callback' }
      expect(success.fetch('if')).to eq('${{ success() }}')
      expect(steps.index(success)).to be > steps.index { |step| step['id'] == 'prepare_next_development_iteration' }
    end

    it 'propagates validation command errors without interpreting an output decision' do
      Dir.mktmpdir do |directory|
        _output, _error, status = run_step('validate_release', directory: directory, command: 'echo invalid >&2; exit 7')
        expect(status.exitstatus).to eq(7)
        expect(File.read(File.join(directory, 'output'))).to eq('')
        expect(File).not_to exist(File.join(directory, 'summary'))
      end
    end

    it 'accepts a successful validation command without any output protocol' do
      Dir.mktmpdir do |directory|
        _output, error, status = run_step('validate_release', directory: directory, command: 'true')
        expect(status.success?).to be(true), error
        expect(File.read(File.join(directory, 'output'))).to eq('')
      end
    end

    it 'propagates a custom command failure through the actual shell wrapper' do
      Dir.mktmpdir do |directory|
        _output, _error, status = run_step('prepare_release', directory: directory, command: 'exit 7')
        expect(status.exitstatus).to eq(7)
      end
    end

    it 'invokes configured validators on every attempt' do
      prepare = steps.find { |step| step['id'] == 'prepare_release' }
      expect(prepare['if']).to be_nil
      Dir.mktmpdir do |directory|
        command = 'echo ran >> "$RUNNER_TEMP/validated"'
        2.times do
          _output, error, status = run_step('validate_release', directory: directory, command: command)
          expect(status.success?).to be(true), error
          expect(File.read(File.join(directory, 'output'))).to eq('')
        end
        expect(File.read(File.join(directory, 'validated'))).to eq("ran\nran\n")
        _output, _error, status = run_step('validate_release', directory: directory, command: 'exit 7')
        expect(status.exitstatus).to eq(7)
      end
    end
  end

  def run_step(id, directory:, command: '')
    values = ENV.to_h.slice('PATH', 'HOME', 'TMPDIR').merge(
      'RUNNER_TEMP' => directory, 'RELEASE_COMMAND' => command,
      'GITHUB_ENV' => File.join(directory, 'environment'), 'GITHUB_OUTPUT' => File.join(directory, 'output'),
      'GITHUB_STEP_SUMMARY' => File.join(directory, 'summary')
    )
    File.write(values.fetch('GITHUB_ENV'), '')
    File.write(values.fetch('GITHUB_OUTPUT'), '')
    step = steps.find { |item| item['id'] == id }
    Open3.capture3(values, 'bash', '-euo', 'pipefail', '-c', step.fetch('run'), unsetenv_others: true)
  end

  context 'with the reusable workflow' do
    let(:workflow) { YAML.load_file('.github/workflows/release.yml') }
    let(:steps) { workflow.fetch('jobs').fetch('release').fetch('steps') }

    it_behaves_like 'a release interface'

    it 'passes the configured timezone to the release job' do
      expect(workflow.dig('jobs', 'release', 'env', 'TZ')).to eq('${{ inputs.timezone }}')
    end
  end

  context 'with the composite action' do
    let(:workflow) { YAML.load_file('action.yml') }
    let(:steps) { workflow.fetch('runs').fetch('steps') }

    it_behaves_like 'a release interface'

    it 'passes the configured timezone to input configuration' do
      expect(steps.find { |step| step['id'] == 'configure_release_inputs' }.dig('env', 'TZ')).to eq('${{ inputs.timezone }}')
    end
  end

  context 'with Danger reporting workflows' do
    let(:producer) { YAML.load_file('.github/workflows/danger.yml') }
    let(:commenter) { YAML.load_file('.github/workflows/danger-comment.yml') }

    it 'uses the released producer defaults with read-only permissions' do
      expect(producer.fetch(true).keys).to eq(['pull_request'])
      expect(producer.fetch('permissions')).to eq('contents' => 'read')
      job = producer.fetch('jobs').fetch('danger')
      expect(job.fetch('uses')).to eq('danger/danger-pr-comment/.github/workflows/danger-run.yml@v0.3.0')
      expect(job.fetch('with')).not_to have_key('danger-args')
      expect(job).not_to have_key('secrets')
    end

    it 'delegates completed-run commenting without executing contribution code' do
      expect(commenter.fetch(true)).to eq('workflow_run' => { 'workflows' => ['Danger'], 'types' => ['completed'] })
      expect(commenter.fetch('permissions')).to eq('actions' => 'read', 'issues' => 'write', 'pull-requests' => 'write')
      job = commenter.fetch('jobs').fetch('comment')
      expect(job).to eq('uses' => 'danger/danger-pr-comment/.github/workflows/danger-comment.yml@v0.3.0')
    end
  end
end
