# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'open3'
require 'tmpdir'
require 'ruby-gem-release/git'

RSpec.describe 'Workflow Git identity' do # rubocop:disable RSpec/DescribeClass -- Execute workflow configuration.
  let(:directory) { Dir.mktmpdir }
  let(:workflow) { YAML.load_file('.github/workflows/release.yml') }

  before do
    system('git', 'init', '--quiet', directory, exception: true)
    system('git', '-C', directory, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com',
           'commit', '--quiet', '--allow-empty', '-m', 'Fixture', exception: true)
  end

  after { FileUtils.remove_entry(directory) }

  def configure_identity(**arguments)
    Dir.chdir(directory) { RubyGemRelease::Git.new(directory: directory).configure!(**arguments) }
  end

  it 'configures the custom identity locally', :aggregate_failures do
    configure_identity(name: 'Release Maintainer', email: 'release@example.com')
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
      expect { configure_identity(name: value) }.to raise_error(ArgumentError, /identity/)
      expect { configure_identity(email: value) }.to raise_error(ArgumentError, /identity/)
    end
  end
end
