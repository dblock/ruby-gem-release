# frozen_string_literal: true

require 'spec_helper'
require_relative '../fixtures/github_release_examples'

RSpec.describe 'Composite action release lifecycle' do
  include_context 'with a GitHub release consumer'

  let(:workflow) { YAML.load_file('action.yml') }

  def steps
    workflow.fetch('runs').fetch('steps')
  end

  def inputs
    workflow.fetch('inputs')
  end

  it_behaves_like 'a local release lifecycle', nil
  it_behaves_like 'a custom registry destination'
  it_behaves_like 'rejects empty release notes'
  it_behaves_like 'a failed publication'
  it_behaves_like 'repeating accepted publication'
end
