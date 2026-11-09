# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/workflow/ruby_gem'
require 'ruby-gem-release/changelog'

RSpec.describe RubyGemRelease::Workflow::RubyGem do
  let(:events) { [] }
  let(:version) { instance_double(RubyGemRelease::Version::RubyConstant) }
  let(:objects) do
    {
      changelog: instance_double(RubyGemRelease::Changelog::KeepAChangelog),
      package: instance_double(RubyGemRelease::Package::RubyGem),
      destination: instance_double(RubyGemRelease::Destination::RubyGems),
      git: instance_double(RubyGemRelease::SourceControl::Git),
      hosting: instance_double(RubyGemRelease::Hosting::GitHubRelease)
    }
  end

  around do |example|
    application = Rake.application
    environment = ENV.to_h
    Rake.application = Rake::Application.new
    ENV.update('RELEASE_VERSION' => '2.0.0', 'RELEASE_PREVIOUS_VERSION' => '1.2.3', 'RELEASE_DATE' => '2026-11-07', 'INPUT_VERSION' => '')
    ENV.delete('GITHUB_OUTPUT')
    %w[RELEASE_STATE RELEASE_STEP_ID RELEASE_STEPS GITHUB_ACTIONS].each { |key| ENV.delete(key) }
    example.run
  ensure
    Rake.application = application
    ENV.replace(environment)
  end

  before do
    allow(version).to receive(:read) do
      events << :read
      '2.0.0'
    end
    allow(version).to receive(:increment!) do
      events << :increment
      '2.0.1'
    end
    record_operations(:changelog, %i[release! prepare_next!])
    allow(objects.fetch(:changelog)).to receive(:pending?).and_return(true)
    record_operations(:package, [:build!])
    allow(objects.fetch(:package)).to receive(:name).and_return('example')
    record_operations(:destination, %i[authenticate! check_version! publish!])
    allow(objects.fetch(:destination)).to receive(:authentication).and_return('rubygems')
    record_operations(:git, %i[commit! tag! push! commit_next!])
    allow(objects.fetch(:git)).to receive(:stage_changes!).and_yield
    record_operations(:hosting, [:publish!])
    allow(RubyGemRelease::Package::RubyGem).to receive(:new).and_return(objects.fetch(:package))
    allow(RubyGemRelease::Destination::RubyGems).to receive(:new).and_return(objects.fetch(:destination))
    allow(RubyGemRelease::SourceControl::Git).to receive(:new).and_return(objects.fetch(:git))
    allow(RubyGemRelease::Hosting::GitHubRelease).to receive(:new).and_return(objects.fetch(:hosting))
  end

  def record_operations(object, methods)
    methods.each do |method|
      allow(objects.fetch(object)).to receive(method) { events << [object, method] }
    end
  end

  def install(**overrides)
    described_class.new(version: version, changelog: objects.fetch(:changelog), **overrides).install_tasks
  end

  def run_callbacks
    %w[validate prepare publish bump].each { |phase| Rake::Task["release:#{phase}"].invoke }
  end

  it 'skips empty pending notes without invoking release operations' do
    allow(objects.fetch(:changelog)).to receive(:pending?).and_return(false)
    install
    expect { Rake::Task['release:validate'].invoke }.to output("Release skipped: nothing to release.\n").to_stdout
    expect(events).to be_empty
  end

  it 'uses custom validation instead of inferring the release decision' do
    received = nil
    install(validate: lambda { |ctx|
      received = ctx.release
      false
    })
    expect { Rake::Task['release:validate'].invoke }.to output("Release skipped: nothing to release.\n").to_stdout
    expect(received).to have_attributes(version: '1.2.3')
    expect(objects.fetch(:changelog)).not_to have_received(:pending?)
  end

  it 'wires default objects in the existing release order without running during installation', :aggregate_failures do
    install
    expect(events).to be_empty
    run_callbacks
    expect(events).to eq([
                           :read, %i[changelog release!], %i[destination authenticate!], %i[destination check_version!], %i[git commit!], %i[package build!], %i[git tag!],
                           %i[destination publish!], %i[git push!], %i[hosting publish!],
                           :increment, %i[changelog prepare_next!], %i[git commit_next!], %i[git push!]
                         ])
  end

  it 'runs configured success and failure callbacks with the appropriate release context', :aggregate_failures do
    received = []
    install = described_class.new(
      version: version,
      changelog: objects.fetch(:changelog),
      success: ->(ctx) { received << [:success, ctx] },
      failure: ->(failure) { received << [:failure, failure] }
    )
    install.install_tasks
    Rake::Task['release:success'].invoke
    Rake::Task['release:failure'].invoke
    expect(received.map(&:first)).to eq(%i[success failure])
    expect(received.first.last).to have_attributes(workflow: install, release: have_attributes(version: '2.0.0', previous_version: '1.2.3'))
    expect(received.last.last).to have_attributes(phase: 'unknown', error: nil, context: have_attributes(workflow: install, release: have_attributes(version: '2.0.0', previous_version: '1.2.3')))
  end

  it 'makes configured components and the completed next development version available to success' do
    received = nil
    instance = described_class.new(version: version, changelog: objects.fetch(:changelog), success: ->(ctx) { received = ctx })
    instance.install_tasks
    run_callbacks
    Rake::Task['release:success'].invoke
    expect(received.release).to have_attributes(version: '2.0.0', next_version: '2.0.1')
    expect(received.workflow).to equal(instance)
    expect(received.workflow.version).to equal(version)
    expect(received.workflow.git).to equal(objects.fetch(:git))
    expect(received.workflow.destination).to equal(objects.fetch(:destination))
  end

  it 'does not record a completed next development iteration when pushing fails' do
    received = nil
    allow(objects.fetch(:git)).to receive(:push!).and_raise('push failed')
    install(failure: ->(failure) { received = failure.context })
    expect { Rake::Task['release:bump'].invoke }.to raise_error('push failed')
    Rake::Task['release:failure'].invoke
    expect(received.release.next_version).to be_nil
  end

  it 'preserves the initial context across version copies', :aggregate_failures do
    received = []
    allow(objects.fetch(:changelog)).to receive(:release!) { |release| received << release }
    allow(objects.fetch(:changelog)).to receive(:prepare_next!) { |release| received << release }
    install
    run_callbacks
    expect(received.map { |release| [release.version, release.previous_version, release.next_version, release.date] })
      .to eq([['2.0.0', '1.2.3', nil, Date.new(2026, 11, 7)], ['2.0.0', '1.2.3', '2.0.1', Date.new(2026, 11, 7)]])
    expect(received).to all(be_frozen)
    expect(objects.fetch(:git)).to have_received(:commit!).with(an_instance_of(RubyGemRelease::Release))
    expect(objects.fetch(:git)).to have_received(:commit_next!).with(received.last)
    expect(objects.fetch(:hosting)).to have_received(:publish!).with(an_instance_of(RubyGemRelease::Release), package: objects.fetch(:package))
  end

  it 'sets a selected version before preparing the changelog and preserves the previous version', :aggregate_failures do
    ENV['INPUT_VERSION'] = '3.0.0'
    allow(version).to receive(:set!).with('3.0.0') { events << :set }
    allow(version).to receive(:read).and_return('3.0.0')
    install
    Rake::Task['release:prepare'].invoke
    expect(events).to eq([:set, %i[changelog release!]])
    expect(objects.fetch(:changelog)).to have_received(:release!).with(have_attributes(version: '3.0.0', previous_version: '1.2.3'))
  end

  it 'sets a selected version even when changelog updates are disabled', :aggregate_failures do
    ENV['INPUT_VERSION'] = '3.0.0'
    allow(version).to receive(:set!).with('3.0.0')
    described_class.new(version: version, changelog: nil).install_tasks
    Rake::Task['release:prepare'].invoke
    expect(version).to have_received(:set!).with('3.0.0')
    expect(objects.fetch(:changelog)).not_to have_received(:release!)
  end

  it 'passes its execution provider to tasks and uses its selected version during preparation' do
    provider = RubyGemRelease::ExecutionProvider.new(environment: ENV.to_h.merge('INPUT_VERSION' => '3.0.0', 'INPUT_GEMSPEC' => 'selected.gemspec'))
    allow(version).to receive(:set!).with('3.0.0')
    instance = described_class.new(version: version, changelog: nil, provider: provider)
    instance.install_tasks
    Rake::Task['release:prepare'].invoke
    expect(version).to have_received(:set!).with('3.0.0')
    expect(RubyGemRelease::Package::RubyGem).to have_received(:new).with(gemspec: 'selected.gemspec', directory: nil)
    expect(instance.provider).to equal(provider)
  end

  it 'rejects invalid selected versions before invoking the setter or changelog', :aggregate_failures do
    ENV['INPUT_VERSION'] = '03.0.0'
    allow(version).to receive(:set!)
    install
    expect { Rake::Task['release:prepare'].invoke }.to raise_error(ArgumentError, /invalid version/)
    expect(version).not_to have_received(:set!)
    expect(events).to be_empty
  end

  it 'requires custom version objects to implement set! only when selecting a version' do
    ENV['INPUT_VERSION'] = '3.0.0'
    custom = Struct.new(:read).new('1.2.3')
    described_class.new(version: custom, changelog: objects.fetch(:changelog)).install_tasks
    expect { Rake::Task['release:prepare'].invoke }.to raise_error(ArgumentError, /must implement set!/)
  end

  it 'uses supplied publication objects instead of constructing defaults', :aggregate_failures do
    install(**objects.except(:changelog))
    Rake::Task['release:publish'].invoke
    expect(RubyGemRelease::Package::RubyGem).not_to have_received(:new)
    expect(RubyGemRelease::Destination::RubyGems).not_to have_received(:new)
    expect(RubyGemRelease::SourceControl::Git).not_to have_received(:new)
    expect(RubyGemRelease::Hosting::GitHubRelease).not_to have_received(:new)
    expect(objects.fetch(:hosting)).to have_received(:publish!).with(an_instance_of(RubyGemRelease::Release), package: objects.fetch(:package))
  end

  it 'passes the configured package to capture as well as publication' do
    environment = instance_double(RubyGemRelease::Workflow::Environment, capture!: nil)
    allow(RubyGemRelease::Workflow::Environment).to receive(:new).and_return(environment)
    install(**objects.except(:changelog))
    Rake::Task['release:workflow:capture'].invoke
    expect(environment).to have_received(:capture!).with(package: objects.fetch(:package))
    expect(RubyGemRelease::Package::RubyGem).not_to have_received(:new)
  end

  it 'disables hosted releases without skipping package publication', :aggregate_failures do
    install(hosting: nil)
    Rake::Task['release:publish'].invoke
    expect(events).to eq([%i[destination authenticate!], %i[destination check_version!], %i[git commit!], %i[package build!], %i[git tag!], %i[destination publish!], %i[git push!]])
    expect(RubyGemRelease::Hosting::GitHubRelease).not_to have_received(:new)
  end

  it 'disables changelog updates but still increments and commits the next development iteration', :aggregate_failures do
    described_class.new(version: version, changelog: nil).install_tasks
    run_callbacks
    expect(events).to include(:increment, %i[git commit_next!])
    expect(events).not_to include(:read, %i[changelog release!], %i[changelog prepare_next!])
  end

  it 'stops publication immediately after a build failure', :aggregate_failures do
    allow(objects.fetch(:package)).to receive(:build!).and_raise('build failed')
    install
    expect { Rake::Task['release:publish'].invoke }.to raise_error('build failed')
    expect(events).to eq([%i[destination authenticate!], %i[destination check_version!], %i[git commit!]])
  end

  it 'stops before pushing or creating a hosted release when the registry destination fails' do
    allow(objects.fetch(:destination)).to receive(:publish!).and_raise('registry unavailable')
    install
    expect { Rake::Task['release:publish'].invoke }.to raise_error('registry unavailable')
    expect(events).to eq([%i[destination authenticate!], %i[destination check_version!], %i[git commit!], %i[package build!], %i[git tag!]])
    expect(objects.fetch(:destination)).to have_received(:publish!).with(an_instance_of(RubyGemRelease::Release), package: objects.fetch(:package))
  end

  it 'checks the exact release version before committing, building, or tagging', :aggregate_failures do
    allow(objects.fetch(:destination)).to receive(:check_version!).with(name: 'example', version: '2.0.0').and_raise('already published')
    install
    expect { Rake::Task['release:publish'].invoke }.to raise_error('already published')
    expect(events).to eq([%i[destination authenticate!]])
  end

  it 'stops before publication operations when destination authentication fails' do
    allow(objects.fetch(:destination)).to receive(:authenticate!).and_raise('authentication failed')
    install
    expect { Rake::Task['release:publish'].invoke }.to raise_error('authentication failed')
    expect(events).to be_empty
  end

  it 'stops before committing when next development iteration changelog preparation fails', :aggregate_failures do
    allow(objects.fetch(:changelog)).to receive(:prepare_next!).and_raise('changelog failed')
    install
    expect { Rake::Task['release:bump'].invoke }.to raise_error('changelog failed')
    expect(events).to eq([:increment])
  end
end
