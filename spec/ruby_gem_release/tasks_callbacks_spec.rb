# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyGemRelease::Tasks do
  around do |example|
    original = Rake.application
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = original
  end

  it 'installs without configuration or version tasks', :aggregate_failures do
    described_class.install
    expect(Rake::Task.task_defined?('release:before_release')).to be(true)
    expect(Rake::Task.task_defined?('release:version:read')).to be(false)
  end

  it 'starts release preparation with the current version and date' do # rubocop:disable RSpec/ExampleLength -- Exercise callback context.
    received = nil
    described_class.install do |tasks|
      tasks.before_release { |release| received = [release.version, release.previous_version, release.next_version, release.date] }
    end
    Rake::Task['release:before_release'].invoke('1.2.3', '1.2.3', '2026-11-07')
    expect(received).to eq(['1.2.3', '1.2.3', nil, Date.new(2026, 11, 7)])
  end

  it 'attaches a prepared version without changing the original context', :aggregate_failures do
    original = RubyGemRelease::Release.new(version: '1.2.3', previous_version: '1.2.3', date: Date.new(2026, 11, 7))
    updated = original.with_version('2.0.0')
    expect([original.version, updated.version, updated.previous_version, updated.next_version]).to eq(['1.2.3', '2.0.0', '1.2.3', nil])
    expect(updated).to be_frozen
  end

  it 'attaches the incremented next version after publication' do # rubocop:disable RSpec/ExampleLength -- Exercise the post-release phase.
    received = nil
    described_class.install do |tasks|
      tasks.after_release do |release|
        updated = release.with_next_version('2.0.1')
        received = [updated.version, updated.previous_version, updated.next_version, updated.date]
      end
    end
    Rake::Task['release:after_release'].invoke('2.0.0', '1.2.3', '2026-11-07')
    expect(received).to eq(['2.0.0', '1.2.3', '2.0.1', Date.new(2026, 11, 7)])
  end

  it 'propagates callback failures' do
    described_class.install do |tasks|
      tasks.before_release { |_| raise 'callback failed' }
    end
    expect { Rake::Task['release:before_release'].invoke('1.2.3', '1.2.3', '2026-11-07') }.to raise_error('callback failed')
  end

  it 'runs successfully without callbacks' do
    described_class.install
    expect do
      Rake::Task['release:before_release'].invoke('1.2.3', '1.2.3', '2026-11-07')
      Rake::Task['release:after_release'].invoke('1.2.3', '1.2.3', '2026-11-07')
    end.not_to raise_error
  end

  it 'rejects invalid version arguments' do
    described_class.install
    expect { Rake::Task['release:before_release'].invoke('invalid', '1.2.3', '2026-11-07') }.to raise_error(ArgumentError, /invalid version/)
  end

  it 'rejects missing and malformed dates' do # rubocop:disable RSpec/ExampleLength -- Exercise invalid date forms.
    described_class.install
    task = Rake::Task['release:before_release']
    [nil, '2026-11-40', '20261107'].each do |date|
      task.reenable
      expect { task.invoke('1.2.3', '1.2.3', date) }.to raise_error(ArgumentError)
    end
  end

  it 'rejects duplicate callback registration' do # rubocop:disable RSpec/ExampleLength -- Register twice to exercise failure.
    expect do
      described_class.install do |tasks|
        tasks.before_release { nil }
        tasks.before_release { nil }
      end
    end.to raise_error(ArgumentError, /already configured/)
  end
end
