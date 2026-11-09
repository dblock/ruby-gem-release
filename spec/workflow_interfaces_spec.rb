# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'open3'
require 'tmpdir'

RSpec.describe 'Release interface contracts' do
  shared_examples 'a release interface' do
    it 'captures after setup, validates before edits, and gates downstream steps' do
      setup = steps.index { |step| step['uses'] == 'ruby/setup-ruby@v1' }
      capture = steps.index { |step| step['id'] == 'capture_release_context' }
      validation = steps.index { |step| step['id'] == 'validate_release' }
      expect(capture).to be > setup
      expect(validation).to be > capture
      %w[prepare_release resolve_prepared_version test_release publish_release
         preserve_release_artifacts prepare_next_development_iteration release_success_callback].each do |id|
        step = steps.find { |item| item['id'] == id }
        expect(steps.index(step)).to be > validation
        expect(step.fetch('if')).to include("steps.validate_release.outputs.proceed == 'true'")
      end
    end

    it 'transports enclosing step identities and observed history to configurable commands' do
      steps.select { |step| step.dig('env', 'COMMAND') }.each do |step|
        expect(step.dig('env', 'RELEASE_STEP_ID')).to eq(step.fetch('id'))
        expect(step.dig('env', 'RELEASE_STEPS')).to eq('${{ toJSON(steps) }}')
      end
    end

    it 'preserves recovery artifacts and enables failure handling before capture' do
      artifacts = steps.find { |step| step['id'] == 'preserve_release_artifacts' }
      expect(artifacts.fetch('if')).to include('always()')
      expect(steps.index(artifacts)).to be > steps.index { |step| step['id'] == 'publish_release' }
      expect(steps.index { |step| step['id'] == 'enable_failure_callback' }).to be < steps.index { |step| step['id'] == 'capture_release_context' }
      phase = steps.find { |step| step['id'] == 'determine_release_failure_phase' }
      failure = steps.find { |step| step['id'] == 'release_failure_callback' }
      expect(phase.dig('env', 'RELEASE_STEPS')).to eq('${{ toJSON(steps) }}')
      expect(phase.fetch('run')).to eq('bundle exec rake release:workflow:failure_phase')
      expect(steps.index(phase)).to be < steps.index(failure)
      expect(failure.fetch('if')).to include("failure() && steps.enable_failure_callback.outcome == 'success'")
      expect(failure.dig('env', 'RELEASE_FAILURE_PHASE')).to be_nil
      success = steps.find { |step| step['id'] == 'release_success_callback' }
      expect(success.fetch('if')).to eq("${{ success() && steps.validate_release.outputs.proceed == 'true' }}")
      expect(steps.index(success)).to be > steps.index { |step| step['id'] == 'prepare_next_development_iteration' }
    end

    it 'resets previous invocation exports and removes stale failure details' do
      Dir.mktmpdir do |directory|
        failure = File.join(directory, 'ruby-gem-release-failure.json')
        File.write(failure, '{"previous":"failure"}')
        _output, error, status = run_step('enable_failure_callback', directory: directory)
        expect(status.success?).to be(true), error
        exports = File.readlines(File.join(directory, 'environment'), chomp: true).to_h { |line| line.split('=', 2) }
        expect(exports).to eq(%w[RELEASE_STATE RELEASE_VERSION RELEASE_PREVIOUS_VERSION RELEASE_DATE RELEASE_INITIAL_COMMIT
                                 RELEASE_FAILURE_PHASE RELEASE_AUTHENTICATION RELEASE_DIRECTORY].to_h { |name| [name, ''] })
        expect(File).not_to exist(failure)
      end
    end

    it 'rejects missing, invalid, duplicate, and failed command decisions instead of skipping' do
      Dir.mktmpdir do |directory|
        [
          'true',
          'echo "proceed=maybe" >> "$GITHUB_OUTPUT"',
          'printf "proceed=true\nproceed=false\n" >> "$GITHUB_OUTPUT"',
          'printf "proceed=true\nproceed=\n" >> "$GITHUB_OUTPUT"',
          'echo "proceed=false" >> "$GITHUB_OUTPUT"; exit 1'
        ].each do |command|
          _output, _error, status = run_step('validate_release', directory: directory, command: command)
          expect(status.success?).to be(false), command
          expect(File.read(File.join(directory, 'output'))).to eq('')
          expect(File).not_to exist(File.join(directory, 'summary'))
          expect(Dir[File.join(directory, 'release-validation.*')]).to be_empty
        end
      end
    end

    [true, false].each do |proceed|
      it "transports a valid #{proceed} decision and only summarizes a skip" do
        Dir.mktmpdir do |directory|
          command = "echo 'proceed=#{proceed}' >> \"$GITHUB_OUTPUT\""
          _output, error, status = run_step('validate_release', directory: directory, command: command)
          expect(status.success?).to be(true), error
          expect(File.read(File.join(directory, 'output'))).to eq("proceed=#{proceed}\n")
          summary = File.join(directory, 'summary')
          proceed ? expect(File).not_to(exist(summary)) : expect(File.read(summary)).to(include('Release skipped'))
          expect(Dir[File.join(directory, 'release-validation.*')]).to be_empty
        end
      end
    end

    it 'propagates a custom command failure through the actual shell wrapper' do
      Dir.mktmpdir do |directory|
        _output, _error, status = run_step('prepare_release', directory: directory, command: 'exit 7')
        expect(status.exitstatus).to eq(7)
      end
    end
  end

  def run_step(id, directory:, command: '')
    values = ENV.to_h.slice('PATH', 'HOME', 'TMPDIR').merge(
      'RUNNER_TEMP' => directory, 'COMMAND' => command,
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
end
