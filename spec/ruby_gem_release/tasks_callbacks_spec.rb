# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyGemRelease::Tasks do
  around do |example|
    original = Rake.application
    environment = ENV.to_h.slice('RELEASE_VERSION', 'RELEASE_PREVIOUS_VERSION', 'RELEASE_DATE', 'INPUT_VERSION', 'RELEASE_FAILURE_PHASE', 'RUNNER_TEMP')
    ENV.update('RELEASE_VERSION' => '2.0.0', 'RELEASE_PREVIOUS_VERSION' => '1.2.3', 'RELEASE_DATE' => '2026-11-07', 'INPUT_VERSION' => '')
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = original
    %w[RELEASE_VERSION RELEASE_PREVIOUS_VERSION RELEASE_DATE INPUT_VERSION RELEASE_FAILURE_PHASE RUNNER_TEMP].each { |key| ENV.delete(key) }
    ENV.update(environment)
  end

  it 'installs without configuration or version tasks', :aggregate_failures do
    described_class.install
    expect(Rake::Task.task_defined?('release:before_release')).to be(true)
    expect(Rake::Task.task_defined?('release:version:read')).to be(false)
  end

  it 'starts release preparation with the current version and date' do
    received = nil
    described_class.install do |tasks|
      tasks.before_release { |release| received = [release.version, release.previous_version, release.next_version, release.date] }
    end
    Rake::Task['release:before_release'].invoke
    expect(received).to eq(['1.2.3', '1.2.3', nil, Date.new(2026, 11, 7)])
  end

  it 'passes the selected version to custom callbacks while retaining the initial version and date' do
    ENV['INPUT_VERSION'] = '3.0.0'
    received = nil
    described_class.install do |tasks|
      tasks.before_release { |release| received = [release.version, release.previous_version, release.date] }
    end
    Rake::Task['release:before_release'].invoke
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
      tasks.after_release do |release|
        updated = release.with_next_version('2.0.1')
        received = [updated.version, updated.previous_version, updated.next_version, updated.date]
      end
    end
    Rake::Task['release:after_release'].invoke
    expect(received).to eq(['2.0.0', '1.2.3', '2.0.1', Date.new(2026, 11, 7)])
  end

  it 'propagates callback failures' do
    described_class.install do |tasks|
      tasks.before_release { |_| raise 'callback failed' }
    end
    expect { Rake::Task['release:before_release'].invoke }.to raise_error('callback failed')
  end

  it 'runs successfully without callbacks' do
    described_class.install
    expect do
      Rake::Task['release:before_release'].invoke
      Rake::Task['release:after_release'].invoke
    end.not_to raise_error
  end

  it 'rejects invalid version arguments' do
    described_class.install
    ENV['RELEASE_PREVIOUS_VERSION'] = 'invalid'
    expect { Rake::Task['release:before_release'].invoke }.to raise_error(ArgumentError, /invalid version/)
  end

  it 'rejects missing and malformed dates' do
    described_class.install
    task = Rake::Task['release:before_release']
    %w[2026-11-40 20261107].each do |date|
      ENV['RELEASE_DATE'] = date
      task.reenable
      expect { task.invoke }.to raise_error(ArgumentError)
    end
  end

  it 'rejects a missing release date instead of using today' do
    described_class.install
    ENV.delete('RELEASE_DATE')
    expect { Rake::Task['release:before_release'].invoke }.to raise_error(KeyError, /RELEASE_DATE/)
  end

  it 'passes the released context to the publication callback' do
    received = nil
    described_class.install do |tasks|
      tasks.publish { |release| received = [release.version, release.previous_version, release.next_version, release.date] }
    end
    Rake::Task['release:publish'].invoke
    expect(received).to eq(['2.0.0', '1.2.3', nil, Date.new(2026, 11, 7)])
  end

  it 'passes the released context to the success callback' do
    received = nil
    described_class.install do |tasks|
      tasks.success { |release| received = release }
    end
    Rake::Task['release:success'].invoke
    expect(received).to have_attributes(version: '2.0.0', previous_version: '1.2.3', date: Date.new(2026, 11, 7))
  end

  it 'passes release context, phase, and captured exception to the failure callback' do
    Dir.mktmpdir do |runner_temp|
      received = nil
      ENV['RUNNER_TEMP'] = runner_temp
      ENV['RELEASE_FAILURE_PHASE'] = 'publish_release'
      described_class.install do |tasks|
        tasks.publish { raise 'publication failed' }
        tasks.failure { |failure| received = failure }
      end
      expect { Rake::Task['release:publish'].invoke }.to raise_error('publication failed')
      Rake::Task['release:failure'].invoke
      expect(received).to have_attributes(phase: 'publish_release', release: have_attributes(version: '2.0.0', previous_version: '1.2.3'))
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
    expect(received).to have_attributes(phase: 'capture_release_context', error: nil, release: nil)
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
        tasks.before_release { nil }
        tasks.before_release { nil }
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
