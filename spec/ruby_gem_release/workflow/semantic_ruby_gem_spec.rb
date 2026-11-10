# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/workflow/semantic_ruby_gem'

RSpec.describe RubyGemRelease::Workflow::SemanticRubyGem do
  let(:values) do
    { 'INPUT_VERSION' => '', 'SOURCE_COMMIT' => 'a' * 40, 'GEMSPEC_VERSION' => '9.9.9',
      'RELEASE_VERSION' => '1.3.0', 'RELEASE_DATE' => '2026-11-09' }
  end
  let(:provider) { RubyGemRelease::ExecutionProvider.new(environment: values) }
  let(:components) do
    {
      version: instance_double(RubyGemRelease::Version::RubyConstant, set!: nil, increment!: '1.3.1', next_version: '1.3.1'),
      git: instance_double(RubyGemRelease::SourceControl::Git, commit!: nil, tag!: nil, push!: nil, commit_next!: nil),
      package: instance_double(RubyGemRelease::Package::RubyGem, name: 'example', build!: nil, built?: false),
      destination: instance_double(RubyGemRelease::Destination, authenticate!: nil, publish!: nil),
      changelog: instance_double(RubyGemRelease::Changelog::Generated, release!: nil, prepare_next!: nil)
    }
  end
  let(:semantic) { instance_double(RubyGemRelease::SemanticRelease, analyze: decision) }
  let(:decision) do
    RubyGemRelease::SemanticRelease::Decision.new(head: 'a' * 40, last_release: { 'tag' => 'v1.2.3', 'version' => '1.2.3', 'commit' => 'b' * 40 },
                                                  commits: [], release_type: 'minor', version: '1.3.0', notes: 'Generated notes.')
  end

  around do |example|
    original = Rake.application
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = original
  end

  before { allow(components.fetch(:git)).to receive(:stage_changes!).and_yield }

  def install(**options)
    described_class.new(**components, semantic_release: semantic, provider: provider, hosting: nil, **options).install_tasks
  end

  def invoke(*tasks)
    tasks.each { |task| Rake::Task["release:#{task}"].invoke }
  end

  it 'analyzes once, sets the selected version rather than the development version, and defaults to no bump' do
    received = nil
    install(success: ->(ctx) { received = ctx })
    invoke('validate')
    Rake::Task['release:validate'].reenable
    invoke('validate', 'prepare', 'publish', 'bump', 'success')
    expect(semantic).to have_received(:analyze).once
    expect(components.fetch(:version)).to have_received(:set!).with('1.3.0')
    expect(components.fetch(:changelog)).to have_received(:release!).with(have_attributes(version: '1.3.0', gemspec_version: '9.9.9', notes: decision.notes))
    expect(components.fetch(:version)).not_to have_received(:increment!)
    expect(components.fetch(:git)).not_to have_received(:commit_next!)
    expect(received).to have_attributes(analysis: have_attributes(version: '1.3.0'), release: have_attributes(version: '1.3.0', gemspec_version: '9.9.9', next_version: nil))
  end

  it 'optionally bumps and records the next development version without replacing analysis' do
    received = nil
    install(bump: true, success: ->(ctx) { received = ctx })
    invoke('validate', 'prepare', 'publish', 'bump', 'success')
    expect(components.fetch(:version)).to have_received(:increment!)
    expect(received.release.next_version).to eq('1.3.1')
    expect(received.analysis.to_h).to eq(decision.to_h)
  end

  it 'rejects a no-release decision without consulting handwritten notes or invoking downstream operations' do
    skipped = RubyGemRelease::SemanticRelease::Decision.new(head: 'a' * 40, last_release: nil, commits: [], release_type: nil, version: nil, notes: nil)
    allow(semantic).to receive(:analyze).and_return(skipped)
    install
    expect { invoke('validate') }.to raise_error(ArgumentError, /Nothing to release/)
    Rake::Task['release:validate'].reenable
    expect { invoke('validate') }.to raise_error(ArgumentError, /Nothing to release/)
    expect(semantic).to have_received(:analyze).once
    %w[prepare publish bump success].each do |task|
      expect { invoke(task) }.to raise_error(ArgumentError, /semantic/)
    end
    expect(components.fetch(:destination)).not_to have_received(:authenticate!)
    expect(components.fetch(:version)).not_to have_received(:set!)
    expect(components.fetch(:package)).not_to have_received(:build!)
    expect(components.fetch(:version)).not_to have_received(:increment!)
  end

  it 'rejects selected-version, initial-commit, and explicit-input changes before publication or authentication' do
    install
    invoke('validate')
    [
      ['RELEASE_VERSION', '1.3.1', /differs/],
      ['SOURCE_COMMIT', 'c' * 40, /another commit/],
      ['INPUT_VERSION', '2.0.0', /explicit version changed/]
    ].each do |key, changed, message|
      original = values[key]
      values[key] = changed
      Rake::Task['release:publish'].reenable
      expect { invoke('publish') }.to raise_error(ArgumentError, message)
      values[key] = original
    end
    expect(components.fetch(:destination)).not_to have_received(:authenticate!)
  end

  it 'rejects preparation before analysis and preserves failure callbacks when state is corrupted' do
    received = nil
    install(failure: ->(failure) { received = failure })
    expect { invoke('prepare') }.to raise_error(ArgumentError, /persisted release decision/)
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'state.json')
      File.write(path, '{')
      values['RELEASE_STATE_FILE'] = path
      invoke('failure')
      expect(received.context.analysis).to be_nil
      expect(received.context.release).to have_attributes(version: '1.3.0')
    end
  end

  it 'supports disabling changelog updates and rejects invalid bump policies' do
    install(changelog: nil)
    invoke('validate', 'prepare')
    expect(components.fetch(:version)).to have_received(:set!).with('1.3.0')
    expect(components.fetch(:changelog)).not_to have_received(:release!)
    expect { described_class.new(version: components.fetch(:version), bump: :patch) }.to raise_error(ArgumentError, /bump/)
  end
end
