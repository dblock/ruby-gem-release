# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/workflow/reviewed_ruby_gem'
require 'ruby-gem-release/changelog/notes'

RSpec.describe RubyGemRelease::Workflow::ReviewedRubyGem do
  let(:values) do
    {
      'SOURCE_REF' => 'refs/heads/7-2-stable', 'SOURCE_COMMIT' => 'a' * 40,
      'RELEASE_VERSION' => '1.2.3', 'GEMSPEC_VERSION' => '1.2.3', 'RELEASE_DATE' => '2026-11-07', 'INPUT_VERSION' => ''
    }
  end
  let(:objects) do
    {
      package: instance_double(RubyGemRelease::Package::RubyGem, built?: false, build!: 'release.gem'),
      destination: instance_double(RubyGemRelease::Destination::RubyGems, authenticate!: nil, publish!: nil),
      git: instance_spy(RubyGemRelease::SourceControl::ReviewedGit, head: 'a' * 40, verify!: nil, preserve!: nil),
      hosting: instance_double(RubyGemRelease::Hosting::GitHubRelease, publish!: nil),
      notes: instance_double(RubyGemRelease::Changelog::Notes, read: '- Reviewed change.')
    }
  end
  let(:workflow) do
    described_class.new(branches: ['7-2-stable'], provider: RubyGemRelease::ExecutionProvider.new(environment: values), **objects)
  end

  around do |example|
    application = Rake.application
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = application
  end

  it 'publishes verified notes and makes the preparation and bump phases read-only' do
    workflow.install_tasks
    %w[validate prepare workflow:checkpoint publish bump].each { |phase| Rake::Task["release:#{phase}"].invoke }
    %i[commit! tag! push! commit_next! stage_changes!].each { |operation| expect(objects.fetch(:git)).not_to have_received(operation) }
    expect(objects.fetch(:package)).to have_received(:build!).twice
    expect(objects.fetch(:git)).to have_received(:preserve!).twice
    expect(objects.fetch(:hosting)).to have_received(:publish!).with(have_attributes(notes: '- Reviewed change.'), package: objects.fetch(:package))
  end

  it 'rejects invalid notes before building or publishing any package' do
    allow(objects.fetch(:notes)).to receive(:read).and_return(' ')
    workflow.install_tasks
    expect { Rake::Task['release:validate'].invoke }.to raise_error(ArgumentError, /nonempty string/)
    expect(objects.fetch(:package)).not_to have_received(:build!)
    expect(objects.fetch(:destination)).not_to have_received(:publish!)
  end

  it 'does not publish when package construction changes the verified source' do
    allow(objects.fetch(:git)).to receive(:preserve!).and_raise('Source changed during build')
    workflow.install_tasks
    expect { Rake::Task['release:publish'].invoke }.to raise_error(/Source changed during build/)
    expect(objects.fetch(:destination)).not_to have_received(:publish!)
    expect(objects.fetch(:hosting)).not_to have_received(:publish!)
  end
end
