# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/workflow/github_permissions'

RSpec.describe RubyGemRelease::Workflow::GitHubPermissions do
  let(:responses) { {} }
  let(:api) { instance_double(RubyGemRelease::GitHubAPI) }
  let(:permissions) { described_class.new(branch: 'main', tag: 'v1.2.3', api: api) }

  before do
    allow(api).to receive(:get) { |path| responses[path] }
    allow(RubyGemRelease::SourceControl::Git).to receive(:command).and_return('')
  end

  def ruleset(id, bypass: 'never', **attributes)
    responses["rulesets/#{id}?includes_parents=true"] = { 'id' => id, 'name' => "Rules #{id}", 'current_user_can_bypass' => bypass, **attributes.transform_keys(&:to_s) }
  end

  it 'verifies push access without sending objects when no rules block the release' do
    expect(permissions.check!).to eq(['Verified GitHub push access to main and tag v1.2.3'])
    expect(RubyGemRelease::SourceControl::Git).to have_received(:command).with('push', '--dry-run', '--porcelain', 'origin', 'HEAD:refs/heads/main')
  end

  it 'explains a token without write access' do
    allow(RubyGemRelease::SourceControl::Git).to receive(:command).and_raise(RuntimeError, 'Git command failed: Permission denied (403)')
    expect { permissions.check! }.to raise_error(/cannot push to main; grant contents: write. Git command failed: Permission denied/)
  end

  it 'rejects branch rules the token cannot bypass and ignores rules it can bypass or that allow the push', :aggregate_failures do
    responses['rules/branches/main'] = [
      { 'type' => 'pull_request', 'ruleset_id' => 1 }, { 'type' => 'required_signatures', 'ruleset_id' => 1 },
      { 'type' => 'required_status_checks', 'ruleset_id' => 2 }, { 'type' => 'deletion', 'ruleset_id' => 3 },
      { 'type' => 'update', 'ruleset_id' => 4 }
    ]
    ruleset(1)
    ruleset(2, bypass: 'always')
    expect { permissions.check! }.to raise_error(
      'GitHub rules would reject the release push: branch main: ruleset "Rules 1" requires pull_request, required_signatures; ' \
      'branch main: ruleset 4 requires update'
    )
  end

  it 'rejects active tag rulesets matching the release tag unless bypassed or excluded', :aggregate_failures do
    responses['rulesets?includes_parents=true&targets=tag'] = [1, 2, 3, 4, 5].map { |id| { 'id' => id } }
    matching = { 'conditions' => { 'ref_name' => { 'include' => ['refs/tags/v*'], 'exclude' => [] } }, 'enforcement' => 'active', 'rules' => [{ 'type' => 'creation' }] }
    ruleset(1, **matching)
    ruleset(2, **matching, bypass: 'exempt')
    ruleset(3, **matching, enforcement: 'evaluate')
    ruleset(4, **matching, conditions: { 'ref_name' => { 'include' => ['~ALL'], 'exclude' => ['refs/tags/v1.*'] } })
    ruleset(5, **matching, rules: [{ 'type' => 'deletion' }])
    expect { permissions.check! }.to raise_error('GitHub rules would reject the release push: tag v1.2.3: ruleset "Rules 1" requires creation')
  end

  it 'skips tag rules when the release tag is unknown' do
    expect(described_class.new(branch: 'main', api: api).check!).to eq(['Verified GitHub push access to main'])
    expect(api).not_to have_received(:get).with('rulesets?includes_parents=true&targets=tag')
  end

  it 'warns about branch protection it cannot inspect' do
    responses['branches/main'] = { 'name' => 'main', 'protected' => true }
    expect(permissions.check!.last).to start_with('Warning: main has branch protection')
  end

  it 'requires a default branch' do
    expect { described_class.new(branch: '', api: api) }.to raise_error(ArgumentError, /default branch/)
  end
end
