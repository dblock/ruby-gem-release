# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyGemRelease::Tasks do
  around do |example|
    original = Rake.application
    environment = ENV.to_h
    %w[RELEASE_STATE RELEASE_STEPS RELEASE_STEP_ID GITHUB_ACTIONS].each { |key| ENV.delete(key) }
    ENV.delete('GITHUB_OUTPUT')
    ENV.update('RELEASE_VERSION' => '2.0.0', 'RELEASE_PREVIOUS_VERSION' => '1.2.3', 'RELEASE_DATE' => '2026-11-07', 'INPUT_VERSION' => '')
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = original
    ENV.replace(environment)
  end

  it 'installs without configuration or version tasks', :aggregate_failures do
    described_class.install
    expect(Rake::Task.task_defined?('release:prepare')).to be(true)
    expect(Rake::Task.task_defined?('release:bump')).to be(true)
    expect(Rake::Task.task_defined?('release:version:read')).to be(false)
  end

  it 'validates the selected release context without producing a decision output' do
    Dir.mktmpdir do |directory|
      ENV['GITHUB_ACTIONS'] = 'true'
      ENV['GITHUB_OUTPUT'] = File.join(directory, 'output')
      ENV['INPUT_VERSION'] = '3.0.0'
      described_class.install do |tasks|
        tasks.validate do |ctx|
          expect(ctx.release).to have_attributes(version: '3.0.0', previous_version: '1.2.3', date: Date.new(2026, 11, 7))
          nil
        end
      end
      Rake::Task['release:validate'].invoke
      expect(File).not_to exist(ENV.fetch('GITHUB_OUTPUT'))
    end
  end

  it 'proceeds when no validation callback is configured' do
    described_class.install
    expect { Rake::Task['release:validate'].invoke }.to output("Release validation passed.\n").to_stdout
  end

  it 'accepts a validator that completes normally without a return value' do
    described_class.install { |tasks| tasks.validate { nil } }
    expect { Rake::Task['release:validate'].invoke }.to output("Release validation passed.\n").to_stdout
  end

  it 'delivers validation exceptions to the failure callback' do
    Dir.mktmpdir do |directory|
      ENV['RUNNER_TEMP'] = directory
      ENV['RELEASE_FAILURE_PHASE'] = 'validate_release'
      ENV['RELEASE_STEP_ID'] = 'validate_release'
      ENV['GITHUB_ACTIONS'] = 'true'
      received = nil
      described_class.install do |tasks|
        tasks.validate { raise ArgumentError, 'invalid changelog' }
        tasks.failure { |failure| received = failure }
      end
      expect { Rake::Task['release:validate'].invoke }.to raise_error(ArgumentError, 'invalid changelog')
      Rake::Task['release:failure'].invoke
      expect(received).to have_attributes(phase: 'validate_release', error: have_attributes(message: 'invalid changelog', original_class: 'ArgumentError'))
    end
  end

  it 'rejects missing and duplicate validation blocks' do
    tasks = described_class.new
    expect { tasks.validate }.to raise_error(ArgumentError, /requires a block/)
    tasks.validate { true }
    expect { tasks.validate { false } }.to raise_error(ArgumentError, /already configured/)
  end

  it 'retains the enclosing validation identity and history when a command invokes another callback' do
    ENV.update('GITHUB_ACTIONS' => 'true', 'RELEASE_STEP_ID' => 'validate_release',
               'RELEASE_STEPS' => JSON.generate('capture_release_context' => { 'outcome' => 'success', 'conclusion' => 'success' }))
    received = nil
    described_class.install do |tasks|
      tasks.success { |ctx| received = ctx }
      tasks.validate do
        Rake::Task['release:success'].invoke
        true
      end
    end
    Rake::Task['release:validate'].invoke
    expect(received.step.id).to eq('validate_release')
    expect(received.steps.fetch('capture_release_context').outcome).to eq('success')
    expect(received.steps).not_to have_key('validate_release')
  end

  it 'starts release preparation with the current version and date' do
    received = nil
    described_class.install do |tasks|
      tasks.prepare { |ctx| received = [ctx.release.version, ctx.release.previous_version, ctx.release.next_version, ctx.release.date] }
    end
    Rake::Task['release:prepare'].invoke
    expect(received).to eq(['1.2.3', '1.2.3', nil, Date.new(2026, 11, 7)])
  end

  it 'keeps one coherent state snapshot per context and reloads it for the next task invocation' do
    Dir.mktmpdir do |directory|
      path = RubyGemRelease::Workflow::State.create!(directory: directory)
      ENV.update('RELEASE_STATE' => path, 'RELEASE_INITIAL_COMMIT' => 'a' * 40)
      decision = RubyGemRelease::SemanticRelease::Decision.new(head: 'a' * 40, last_release: nil, commits: [],
                                                               release_type: 'major', version: '2.0.0', notes: 'Original notes.')
      state = RubyGemRelease::Workflow::State.new(path: path)
      state.record_analysis!(decision)
      state.record_next_version!('2.0.1')
      updated = JSON.parse(File.read(path))
      updated['next_version'] = '2.0.2'
      updated.fetch('analysis')['notes'] = 'Updated notes.'
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(path).and_wrap_original do |read, *arguments|
        read.call(*arguments).tap { File.write(path, JSON.generate(updated)) }
      end
      received = []
      described_class.install { |tasks| tasks.success { |ctx| received << ctx } }
      Rake::Task['release:success'].invoke
      Rake::Task['release:success'].reenable
      Rake::Task['release:success'].invoke
      expect(received.first.release).to have_attributes(next_version: '2.0.1', notes: 'Original notes.')
      expect(received.first.analysis.notes).to eq('Original notes.')
      expect(received.last.release).to have_attributes(next_version: '2.0.2', notes: 'Updated notes.')
      expect(received.last.analysis.notes).to eq('Updated notes.')
    end
  end

  it 'passes the selected version to custom callbacks while retaining the initial version and date' do
    ENV['INPUT_VERSION'] = '3.0.0'
    received = nil
    described_class.install do |tasks|
      tasks.prepare { |ctx| received = [ctx.release.version, ctx.release.previous_version, ctx.release.date] }
    end
    Rake::Task['release:prepare'].invoke
    expect(received).to eq(['3.0.0', '1.2.3', Date.new(2026, 11, 7)])
  end

  it 'attaches a prepared version without changing the original context', :aggregate_failures do
    original = RubyGemRelease::Release.new(version: '1.2.3', previous_version: '1.2.3', date: Date.new(2026, 11, 7))
    updated = original.with_version('2.0.0')
    expect([original.version, updated.version, updated.previous_version, updated.next_version]).to eq(['1.2.3', '2.0.0', '1.2.3', nil])
    expect(updated).to be_frozen
  end

  it 'attaches the version for the next development iteration after publication' do
    received = nil
    described_class.install do |tasks|
      tasks.bump do |ctx|
        updated = ctx.release.with_next_version('2.0.1')
        received = [updated.version, updated.previous_version, updated.next_version, updated.date]
      end
    end
    Rake::Task['release:bump'].invoke
    expect(received).to eq(['2.0.0', '1.2.3', '2.0.1', Date.new(2026, 11, 7)])
  end

  it 'propagates callback failures' do
    described_class.install do |tasks|
      tasks.prepare { |_| raise 'callback failed' }
    end
    expect { Rake::Task['release:prepare'].invoke }.to raise_error('callback failed')
  end

  it 'runs successfully without callbacks' do
    described_class.install
    expect do
      Rake::Task['release:prepare'].invoke
      Rake::Task['release:bump'].invoke
    end.not_to raise_error
  end

  it 'rejects invalid version arguments' do
    described_class.install
    ENV['RELEASE_PREVIOUS_VERSION'] = 'invalid'
    expect { Rake::Task['release:prepare'].invoke }.to raise_error(ArgumentError, /invalid version/)
  end

  it 'rejects missing and malformed dates' do
    described_class.install
    task = Rake::Task['release:prepare']
    %w[2026-11-40 20261107].each do |date|
      ENV['RELEASE_DATE'] = date
      task.reenable
      expect { task.invoke }.to raise_error(ArgumentError)
    end
  end

  it 'rejects a missing release date instead of using today' do
    described_class.install
    ENV.delete('RELEASE_DATE')
    expect { Rake::Task['release:prepare'].invoke }.to raise_error(KeyError, /RELEASE_DATE/)
  end

  it 'passes the released context to the publication callback' do
    received = nil
    described_class.install do |tasks|
      tasks.publish { |ctx| received = [ctx.release.version, ctx.release.previous_version, ctx.release.next_version, ctx.release.date] }
    end
    Rake::Task['release:publish'].invoke
    expect(received).to eq(['2.0.0', '1.2.3', nil, Date.new(2026, 11, 7)])
  end

  it 'passes the released context to the success callback' do
    received = nil
    described_class.install do |tasks|
      tasks.success { |ctx| received = ctx.release }
    end
    Rake::Task['release:success'].invoke
    expect(received).to have_attributes(version: '2.0.0', previous_version: '1.2.3', date: Date.new(2026, 11, 7))
  end

  it 'passes release context, phase, and captured exception to the failure callback' do
    Dir.mktmpdir do |runner_temp|
      received = nil
      ENV['RUNNER_TEMP'] = runner_temp
      ENV['RELEASE_FAILURE_PHASE'] = 'publish_release'
      ENV['RELEASE_STEP_ID'] = 'publish_release'
      ENV['GITHUB_ACTIONS'] = 'true'
      described_class.install do |tasks|
        tasks.publish { raise 'publication failed' }
        tasks.failure { |failure| received = failure }
      end
      expect { Rake::Task['release:publish'].invoke }.to raise_error('publication failed')
      Rake::Task['release:failure'].invoke
      expect(received).to have_attributes(phase: 'publish_release', context: have_attributes(release: have_attributes(version: '2.0.0', previous_version: '1.2.3')))
      expect(received.error).to have_attributes(original_class: 'RuntimeError', message: 'publication failed')
    end
  end

  it 'provides phase and nil error when failure details were not captured' do
    received = nil
    ENV.delete('RELEASE_DATE')
    ENV.delete('RUNNER_TEMP')
    ENV['RELEASE_FAILURE_PHASE'] = 'capture_release_context'
    described_class.install do |tasks|
      tasks.failure { |failure| received = failure }
    end
    Rake::Task['release:failure'].invoke
    expect(received).to have_attributes(phase: 'capture_release_context', error: nil, context: have_attributes(release: nil))
  end

  it 'attributes errors to the enclosing Actions step even when it invokes a different task' do
    Dir.mktmpdir do |directory|
      ENV.update('GITHUB_ACTIONS' => 'true', 'RUNNER_TEMP' => directory, 'RELEASE_STEP_ID' => 'custom_prepare', 'RELEASE_FAILURE_PHASE' => 'custom_prepare')
      received = nil
      described_class.install do |tasks|
        tasks.publish { raise 'custom command failed' }
        tasks.failure { |failure| received = failure }
      end
      expect { Rake::Task['release:publish'].invoke }.to raise_error('custom command failed')
      ENV['RELEASE_STEP_ID'] = 'notify_failure'
      Rake::Task['release:failure'].invoke
      expect(received.phase).to eq('custom_prepare')
      expect(received.context.step.id).to eq('notify_failure')
      expect(received.context).to be_an_instance_of(RubyGemRelease::ExecutionContext::GitHub)
      expect(received.error.message).to eq('custom command failed')
    end
  end

  it 'retains explicitly recorded state between local callbacks without changing earlier snapshots' do
    original = nil
    received = nil
    described_class.install do |tasks|
      tasks.bump do |ctx|
        original = ctx
        ctx.record_next_version!('2.0.1')
      end
      tasks.success { |ctx| received = ctx }
    end
    Rake::Task['release:bump'].invoke
    Rake::Task['release:success'].invoke
    expect(original.release.next_version).to be_nil
    expect(received.release.next_version).to eq('2.0.1')
    expect(received.step.id).to eq('release:success')
    expect(received.workflow).to be_nil
    expect(received).to be_an_instance_of(RubyGemRelease::ExecutionContext)
  end

  it 'rejects false validation results through the injected provider without emitting a skip' do
    values = ENV.to_h.merge('GITHUB_ACTIONS' => 'true', 'INPUT_VERSION' => '3.0.0', 'RELEASE_STEPS' => 'not JSON')
    provider = RubyGemRelease::ExecutionProvider.new(environment: values)
    received = nil
    described_class.install(provider: provider) do |tasks|
      tasks.validate do |ctx|
        received = ctx
        false
      end
    end
    expect { Rake::Task['release:validate'].invoke }.to raise_error(ArgumentError, /validation failed/)
    expect(provider.outputs).to be_empty
    expect(received).to be_an_instance_of(RubyGemRelease::ExecutionContext)
    expect(received.release.version).to eq('3.0.0')
  end

  it 'captures and delivers failures through an injected provider without Actions transport' do
    Dir.mktmpdir do |directory|
      provider = RubyGemRelease::ExecutionProvider.new(environment: ENV.to_h.merge('RELEASE_DIRECTORY' => directory))
      allow(provider).to receive(:failed_steps).and_return(['release:publish'])
      received = nil
      described_class.install(provider: provider) do |tasks|
        tasks.publish { raise 'custom provider failure' }
        tasks.failure { |failure| received = failure }
      end
      expect { Rake::Task['release:publish'].invoke }.to raise_error('custom provider failure')
      Rake::Task['release:workflow:failure_phase'].invoke
      Rake::Task['release:failure'].invoke
      expect(received).to have_attributes(phase: 'release:publish', error: have_attributes(message: 'custom provider failure'))
      expect(received.context).to be_an_instance_of(RubyGemRelease::ExecutionContext)
      expect(File.stat(File.join(directory, 'ruby-gem-release-failure.json')).mode & 0o777).to eq(0o600)
    end
  end

  it 'reports corrupt state failures without losing execution metadata or replacing the original error' do
    Dir.mktmpdir do |directory|
      path = File.join(directory, 'state.json')
      File.write(path, '{')
      ENV.update('GITHUB_ACTIONS' => 'true', 'RUNNER_TEMP' => directory, 'RELEASE_STATE' => path, 'RELEASE_STEP_ID' => 'publish_release', 'RELEASE_FAILURE_PHASE' => 'publish_release')
      received = nil
      described_class.install do |tasks|
        tasks.publish { raise 'must not run' }
        tasks.failure { |failure| received = failure }
      end
      expect { Rake::Task['release:publish'].invoke }.to raise_error(JSON::ParserError)
      ENV['RELEASE_STEP_ID'] = 'release_failure_callback'
      expect { Rake::Task['release:failure'].invoke }.to output(/Unable to read release state/).to_stderr
      expect(received.error.original_class).to eq('JSON::ParserError')
      expect(received.context).to have_attributes(step: have_attributes(id: 'release_failure_callback'), release: have_attributes(version: '2.0.0', next_version: nil))
    end
  end

  it 'does nothing when publication is not configured' do
    described_class.install
    ENV.delete('RELEASE_VERSION')
    expect { Rake::Task['release:publish'].invoke }.not_to raise_error
  end

  it 'propagates publication failures' do
    described_class.install do |tasks|
      tasks.publish { |_| raise 'publication failed' }
    end
    expect { Rake::Task['release:publish'].invoke }.to raise_error('publication failed')
  end

  it 'rejects duplicate publication callbacks' do
    expect do
      described_class.install do |tasks|
        tasks.publish { nil }
        tasks.publish { nil }
      end
    end.to raise_error(ArgumentError, /publish already configured/)
  end

  it 'rejects duplicate callback registration' do
    expect do
      described_class.install do |tasks|
        tasks.prepare { nil }
        tasks.prepare { nil }
      end
    end.to raise_error(ArgumentError, /already configured/)
  end

  it 'rejects duplicate result callback registration' do
    expect do
      described_class.install do |tasks|
        tasks.success { true }
        tasks.success { true }
        tasks.failure { true }
        tasks.failure { true }
      end
    end.to raise_error(ArgumentError, /success already configured/)
  end
end
