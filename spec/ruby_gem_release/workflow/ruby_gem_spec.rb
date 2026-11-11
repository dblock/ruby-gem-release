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
      package: instance_double(RubyGemRelease::Package::RubyGem, built?: false),
      destination: instance_double(RubyGemRelease::Destination::RubyGems),
      git: instance_double(RubyGemRelease::SourceControl::Git),
      hosting: instance_double(RubyGemRelease::Hosting::GitHubRelease)
    }
  end

  around do |example|
    application = Rake.application
    environment = ENV.to_h
    Rake.application = Rake::Application.new
    ENV.update('RELEASE_VERSION' => '2.0.0', 'GEMSPEC_VERSION' => '1.2.3', 'RELEASE_DATE' => '2026-11-07', 'INPUT_VERSION' => '')
    ENV.delete('GITHUB_OUTPUT')
    %w[RELEASE_STATE_FILE RELEASE_STEP_ID RELEASE_STEPS_JSON RELEASE_DATA_DIR GEMSPEC_PATH GITHUB_ACTIONS].each { |key| ENV.delete(key) }
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
    allow(objects.fetch(:changelog)).to receive_messages(pending?: true, released?: false)
    record_operations(:package, [:build!])
    record_operations(:destination, %i[authenticate! publish!])
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

  it 'rejects empty pending notes without invoking release operations' do
    allow(objects.fetch(:changelog)).to receive(:pending?).and_return(false)
    install
    expect { Rake::Task['release:validate'].invoke }.to raise_error(ArgumentError, /Nothing to release/)
    expect(events).to be_empty
  end

  it 'checkpoints the exact release before publication or authentication' do
    install
    Rake::Task['release:workflow:checkpoint'].invoke
    expect(events).to eq([%i[git commit!], %i[package build!], %i[git tag!]])
  end

  it 'repeats the bump from the release version without consulting recorded completion' do
    install
    2.times do
      Rake::Task['release:bump'].reenable
      Rake::Task['release:bump'].invoke
    end
    expect(version).to have_received(:increment!).with(from: '2.0.0').twice
    expect(objects.fetch(:git)).to have_received(:commit_next!).twice
  end

  it 'rejects an Actions checkpoint without a configured workflow' do
    RubyGemRelease::Tasks.install
    expect { Rake::Task['release:workflow:checkpoint'].invoke }.to raise_error(/must implement checkpoint!/)
    expect(events).to be_empty
  end

  it 'uses custom validation instead of inferring the release decision' do
    received = nil
    install(validate: lambda { |ctx|
      received = ctx.release
      false
    })
    expect { Rake::Task['release:validate'].invoke }.to raise_error(ArgumentError, /validation failed/)
    expect(received).to have_attributes(version: '1.2.3')
    expect(objects.fetch(:changelog)).not_to have_received(:pending?)
  end

  it 'wires default objects in the existing release order without running during installation', :aggregate_failures do
    install
    expect(events).to be_empty
    run_callbacks
    expect(events).to eq([
                           :read, %i[changelog release!], %i[destination authenticate!], %i[git commit!], %i[package build!], %i[git tag!],
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
    expect(received.first.last).to have_attributes(workflow: install, release: have_attributes(version: '2.0.0', gemspec_version: '1.2.3'))
    expect(received.last.last).to have_attributes(phase: 'unknown', error: nil, context: have_attributes(workflow: install, release: have_attributes(version: '2.0.0', gemspec_version: '1.2.3')))
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
    expect(received.map { |release| [release.version, release.gemspec_version, release.next_version, release.date] })
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
    expect(objects.fetch(:changelog)).to have_received(:release!).with(have_attributes(version: '3.0.0', gemspec_version: '1.2.3'))
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
    provider = RubyGemRelease::ExecutionProvider.new(environment: ENV.to_h.merge('INPUT_VERSION' => '3.0.0', 'INPUT_GEMSPEC_PATH' => 'selected.gemspec'))
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
    expect(events).to eq([%i[destination authenticate!], %i[git commit!], %i[package build!], %i[git tag!], %i[destination publish!], %i[git push!]])
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
    expect(events).to eq([%i[destination authenticate!], %i[git commit!]])
  end

  it 'stops before pushing or creating a hosted release when the registry destination fails' do
    allow(objects.fetch(:destination)).to receive(:publish!).and_raise('registry unavailable')
    install
    expect { Rake::Task['release:publish'].invoke }.to raise_error('registry unavailable')
    expect(events).to eq([%i[destination authenticate!], %i[git commit!], %i[package build!], %i[git tag!]])
    expect(objects.fetch(:destination)).to have_received(:publish!).with(an_instance_of(RubyGemRelease::Release), package: objects.fetch(:package))
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

  it 'runs additive preparation hooks in order inside trusted staging without replacing the changelog' do
    trusted = false
    allow(objects.fetch(:git)).to receive(:stage_changes!) do |&block|
      trusted = true
      block.call
      trusted = false
    end
    workflow = described_class.new(version: version, changelog: objects.fetch(:changelog))
    %i[before after].each do |timing|
      2.times do |index|
        workflow.public_send(timing, :prepare_release) do |ctx|
          expect(trusted).to be(true)
          expect(ctx).to have_attributes(workflow: workflow, stage: :prepare_release, hook: timing, hook_index: index + 1)
          events << [timing, index]
        end
      end
    end
    workflow.install_tasks
    Rake::Task['release:prepare'].invoke
    expect(events).to eq([[:before, 0], [:before, 1], :read, %i[changelog release!], [:after, 0], [:after, 1]])
  end

  it 'retains built-in validation and suppresses after hooks when it fails' do
    workflow = described_class.new(version: version, changelog: objects.fetch(:changelog))
    workflow.before(:validate) { events << :before_validate }
    workflow.after(:validate) { events << :after_validate }
    allow(objects.fetch(:changelog)).to receive(:pending?).and_return(false)
    workflow.install_tasks
    expect { Rake::Task['release:validate'].invoke }.to raise_error(ArgumentError, /Nothing to release/)
    expect(events).to eq([:before_validate])
  end

  it 'does not run validation after hooks when a replacement validator returns false' do
    workflow = described_class.new(version: version, changelog: nil, validate: ->(_) { false })
    workflow.after(:validate) { events << :after_validate }
    workflow.install_tasks
    expect { Rake::Task['release:validate'].invoke }.to raise_error(ArgumentError, /callback returned false/)
    expect(events).to be_empty
  end

  it 'supplies the calculated next version before the development commit and distinguishes both pushes' do
    workflow = described_class.new(version: version, changelog: objects.fetch(:changelog))
    %i[prepare_next push_release push_next].each do |stage|
      workflow.after(stage) { |ctx| events << [stage, ctx.release.next_version] }
    end
    workflow.install_tasks
    run_callbacks
    expect(events.last(8)).to eq([
                                   [:push_release, nil], %i[hosting publish!], :increment, %i[changelog prepare_next!],
                                   [:prepare_next, '2.0.1'], %i[git commit_next!], %i[git push!], [:push_next, '2.0.1']
                                 ])
  end

  it 'preserves result callbacks between ordered hooks and exposes the original failure' do
    workflow = described_class.new(version: version, changelog: nil,
                                   success: ->(_) { events << :success_callback }, failure: ->(_) { events << :failure_callback })
    %i[success failure].each do |stage|
      workflow.before(stage) do |ctx|
        expect(ctx.failure).to be_a(RubyGemRelease::ReleaseFailure) if stage == :failure
        events << :"before_#{stage}"
      end
      workflow.after(stage) { events << :"after_#{stage}" }
    end
    workflow.install_tasks
    Rake::Task['release:success'].invoke
    Rake::Task['release:failure'].invoke
    expect(events).to eq(%i[before_success success_callback after_success before_failure failure_callback after_failure])
  end

  it 'captures the exact failing stage and hook without changing the exception class' do
    Dir.mktmpdir do |directory|
      ENV.update('RELEASE_DATA_DIR' => directory, 'RELEASE_FAILED_STEP_ID' => 'release:prepare')
      received = nil
      workflow = described_class.new(version: version, changelog: nil, failure: ->(failure) { received = failure })
      workflow.before(:prepare_release) { events << :first }
      workflow.before(:prepare_release) { raise ArgumentError, 'project notes invalid' }
      workflow.after(:prepare_release) { events << :after }
      workflow.install_tasks
      expect { Rake::Task['release:prepare'].invoke }.to raise_error(ArgumentError, 'project notes invalid')
      Rake::Task['release:failure'].invoke
      expect(received.error).to have_attributes(original_class: 'ArgumentError', stage: :prepare_release, hook: :before, hook_index: 2)
      expect(events).to eq([:first])
    end
  end

  it 'reports built-in operation failures with their lifecycle stage' do
    Dir.mktmpdir do |directory|
      ENV.update('RELEASE_DATA_DIR' => directory, 'RELEASE_FAILED_STEP_ID' => 'release:publish')
      received = nil
      allow(objects.fetch(:package)).to receive(:build!).and_raise('build failed')
      install(failure: ->(failure) { received = failure })
      expect { Rake::Task['release:publish'].invoke }.to raise_error('build failed')
      Rake::Task['release:failure'].invoke
      expect(received.error).to have_attributes(stage: :build_package, hook: nil, hook_index: nil)
    end
  end

  it 'rejects unknown stages and hooks without a block at registration' do
    workflow = described_class.new(version: version, changelog: nil)
    expect { workflow.before(:push) { nil } }.to raise_error(ArgumentError, /unknown lifecycle stage/)
    expect { workflow.after(:validate) }.to raise_error(ArgumentError, /requires a block/)
  end

  it 'runs checkpoint and publication preparation hooks in both tasks' do
    workflow = described_class.new(version: version, changelog: nil, hosting: nil)
    %i[checkpoint commit_release build_package tag_release publish_registry publish_hosted_release].each do |stage|
      workflow.before(stage) { events << stage }
    end
    workflow.install_tasks
    Rake::Task['release:workflow:checkpoint'].invoke
    2.times do
      Rake::Task['release:publish'].reenable
      Rake::Task['release:publish'].invoke
    end
    expect(events.count(:checkpoint)).to eq(1)
    expect(events.count(:build_package)).to eq(3)
    expect(events.count(:commit_release)).to eq(3)
    expect(events.count(:tag_release)).to eq(3)
    expect(events.count(:publish_registry)).to eq(2)
    expect(events).not_to include(:publish_hosted_release)
  end

  it 'skips authentication hooks when the destination already verifies the exact publication' do
    allow(objects.fetch(:package)).to receive(:built?).and_return(true)
    allow(objects.fetch(:destination)).to receive(:published?).and_return(true)
    workflow = described_class.new(version: version, changelog: nil)
    workflow.before(:authenticate) { events << :authenticate_hook }
    workflow.install_tasks
    Rake::Task['release:publish'].invoke
    expect(events).not_to include(:authenticate_hook, %i[destination authenticate!])
  end

  it 'does not run subsequent hooks after an after hook fails' do
    workflow = described_class.new(version: version, changelog: nil)
    workflow.after(:prepare_release) { raise 'readme update failed' }
    workflow.after(:prepare_release) { events << :unreachable }
    workflow.install_tasks
    expect { Rake::Task['release:prepare'].invoke }.to raise_error('readme update failed')
    expect(events).to be_empty
  end

  it 'does not overwrite the original captured error when a failure hook fails' do
    Dir.mktmpdir do |directory|
      ENV.update('RELEASE_DATA_DIR' => directory, 'RELEASE_FAILED_STEP_ID' => 'release:validate')
      workflow = described_class.new(version: version, changelog: nil, validate: ->(_) { raise 'original validation error' })
      workflow.before(:failure) { raise 'notification failed' }
      workflow.after(:failure) { events << :unreachable }
      workflow.install_tasks
      expect { Rake::Task['release:validate'].invoke }.to raise_error('original validation error')
      expect { Rake::Task['release:failure'].invoke }.to raise_error('notification failed')
      original = RubyGemRelease::Workflow::Failure.error_for('release:validate', provider: workflow.provider)
      expect(original).to have_attributes(message: 'original validation error', stage: :validate)
      expect(events).to be_empty
    end
  end

  it 'retains concurrency checks before registry publication' do
    allow(objects.fetch(:git)).to receive(:tag!).and_raise('Default branch advanced; start a new release')
    install
    expect { Rake::Task['release:publish'].invoke }.to raise_error(/Default branch advanced/)
    expect(objects.fetch(:destination)).not_to have_received(:publish!)
    expect(objects.fetch(:package)).to have_received(:build!)
  end

  it 'runs result hooks without requiring replacement result callbacks' do
    workflow = described_class.new(version: version, changelog: nil)
    workflow.after(:success) { events << :success_hook }
    workflow.after(:failure) { events << :failure_hook }
    workflow.install_tasks
    Rake::Task['release:success'].invoke
    Rake::Task['release:failure'].invoke
    expect(events).to eq(%i[success_hook failure_hook])
  end
end
