# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/execution_context/github'

RSpec.describe RubyGemRelease::ExecutionContext::GitHub do
  let(:release) { RubyGemRelease::Release.new(version: '1.2.3', previous_version: '1.2.3', date: Date.new(2026, 11, 9)) }

  def build_ctx(environment = {})
    described_class.new(release: release, task: 'release:prepare', state: RubyGemRelease::Workflow::State.new, environment: environment)
  end

  it 'preserves step outcomes separately from conclusions and exposes only supported outputs' do
    ctx = build_ctx(
      'RELEASE_STEP_ID' => 'custom_prepare',
      'RELEASE_STEPS' => JSON.generate(
        'validate_release' => { 'outcome' => 'success', 'conclusion' => 'success', 'outputs' => { 'proceed' => 'true', 'private' => 'hidden' } },
        'optional_check' => { 'outcome' => 'failure', 'conclusion' => 'success' },
        'unused_auth' => { 'outcome' => 'skipped', 'conclusion' => 'skipped' }
      )
    )
    expect(ctx.step.id).to eq('custom_prepare')
    expect(ctx.step.outcome).to be_nil
    expect(ctx.steps.fetch('optional_check')).to have_attributes(outcome: 'failure', conclusion: 'success')
    expect(ctx.steps.fetch('unused_auth').outcome).to eq('skipped')
    expect(ctx.steps['not_observed']).to be_nil
    expect(ctx.steps.fetch('validate_release').outputs).to eq('proceed' => 'true')
    expect { ctx.steps.fetch('validate_release').outputs.fetch('proceed').replace('false') }.to raise_error(FrozenError)
    expect { ctx.steps.clear }.to raise_error(FrozenError)
    expect(ctx.steps.values).to all(be_frozen)
  end

  it 'copies only public GitHub run metadata and leaves absent fields unavailable' do
    environment = { 'GITHUB_REPOSITORY' => +'owner/gem', 'GITHUB_RUN_ID' => '123', 'GITHUB_RUN_ATTEMPT' => '2', 'GH_TOKEN' => 'private' }
    ctx = build_ctx(environment)
    environment.fetch('GITHUB_REPOSITORY').replace('changed')
    expect(ctx.run).to have_attributes(repository: 'owner/gem', run_id: '123', run_attempt: '2', sha: nil)
    expect(ctx.run).not_to respond_to(:token)
    expect(ctx.run).to be_frozen
    expect(build_ctx.step.id).to eq('release:prepare')
    expect(build_ctx.steps).to be_empty
  end

  it 'rejects malformed or invalid step snapshots instead of inventing execution history' do
    ['[]', '{"bad":null}', '{"bad":{"outcome":"invented"}}', '{"bad":{"outputs":[]}}'].each do |json|
      expect { build_ctx('RELEASE_STEPS' => json) }.to raise_error(ArgumentError)
    end
    expect { build_ctx('RELEASE_STEPS' => '{') }.to raise_error(JSON::ParserError)
  end
end
