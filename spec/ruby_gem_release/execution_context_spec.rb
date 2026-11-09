# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyGemRelease::ExecutionContext do
  it 'keeps local execution independent of provider environment and immutable across state updates' do
    original = ENV.to_h
    ENV.update('RELEASE_STEP_ID' => 'github_step', 'RELEASE_STEPS' => 'invalid json', 'GITHUB_REPOSITORY' => 'owner/gem')
    release = RubyGemRelease::Release.new(version: '1.2.3', previous_version: '1.2.3', date: Date.new(2026, 11, 9))
    state = RubyGemRelease::Workflow::State.new
    ctx = described_class.new(release: release, task: 'release:prepare', state: state)
    ctx.record_next_version!('1.2.4')
    expect(ctx.step.id).to eq('release:prepare')
    expect(ctx.step).not_to respond_to(:conclusion)
    expect(ctx.steps).to be_empty
    expect(ctx.run).to be_nil
    expect(ctx.release.next_version).to be_nil
    expect(state.next_version).to eq('1.2.4')
    expect(ctx).to be_frozen
  ensure
    ENV.replace(original)
  end
end
