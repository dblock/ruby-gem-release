# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/workflow/ruby_gem'
require_relative '../../../examples/gitlab_semantic_release/semantic_release'

RSpec.describe GitLabSemanticReleaseExample::SemanticRelease do
  let(:provider) { RubyGemRelease::ExecutionProvider.new(environment: {}) }
  let(:workflow) { instance_double(RubyGemRelease::Workflow::RubyGem, provider: provider) }
  let(:ctx) { instance_double(RubyGemRelease::ExecutionContext, workflow: workflow) }
  let(:decision) { described_class.new }

  it 'exports the selected version for standard preparation' do
    allow(decision).to receive(:version_for).with(ctx).and_return('2.0.0')
    expect(decision.proceed?(ctx)).to be(true)
    expect(provider.fetch('INPUT_VERSION')).to eq('2.0.0')
  end

  it 'skips successfully without exporting a version when no release is needed' do
    allow(decision).to receive(:version_for).with(ctx).and_return(nil)
    expect(decision.proceed?(ctx)).to be(false)
    expect(provider.fetch('INPUT_VERSION', nil)).to be_nil
  end

  it 'rejects invalid decisions before exporting a selected version' do
    allow(decision).to receive(:version_for).with(ctx).and_return('02.0.0')
    expect { decision.proceed?(ctx) }.to raise_error(ArgumentError, /MAJOR.MINOR.PATCH/)
    expect(provider.fetch('INPUT_VERSION', nil)).to be_nil
  end

  it 'fails explicitly until semantic analysis is implemented' do
    expect { decision.proceed?(ctx) }.to raise_error(NotImplementedError, /Discover release history/)
    expect(provider.fetch('INPUT_VERSION', nil)).to be_nil
  end
end
