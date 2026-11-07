# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe RubyGemRelease::Tasks do
  let(:directory) { Dir.mktmpdir }
  let(:version_file) { File.join(directory, 'version.rb') }

  around do |example|
    original = Rake.application
    Rake.application = Rake::Application.new
    example.run
  ensure
    Rake.application = original
  end

  before { File.write(version_file, "VERSION = '1.2.3'\n") }
  after { FileUtils.remove_entry(directory) }

  it 'passes the release date and version before setting the version' do # rubocop:disable RSpec/ExampleLength -- Check callback arguments and version ordering.
    received = nil
    described_class.install(version_file: version_file, version_constant: 'VERSION') do |release|
      release.before_release { |version:, date:| received = [version, date, File.read(version_file)] }
    end
    Rake::Task['release:before_release'].invoke('2.0.0')
    expect(received).to eq(['2.0.0', Date.today, "VERSION = '1.2.3'\n"])
  end

  it 'passes the bumped version and released version after the bump', :aggregate_failures do # rubocop:disable RSpec/ExampleLength -- Exercise the task sequence.
    received = nil
    described_class.install(version_file: version_file, version_constant: 'VERSION') do |release|
      release.after_bump { |version:, released_version:| received = [version, released_version] }
    end
    Rake::Task['release:version:set'].invoke('2.0.0')
    Rake::Task['release:version:bump'].invoke
    Rake::Task['release:after_bump'].invoke('2.0.0')
    expect(received).to eq(%w[2.0.1 2.0.0])
  end

  it 'propagates callback failures' do
    described_class.install(version_file: version_file, version_constant: 'VERSION') do |release|
      release.before_release { |**| raise 'callback failed' }
    end
    expect { Rake::Task['release:before_release'].invoke('1.2.3') }.to raise_error('callback failed')
  end

  it 'allows no callbacks but rejects invalid version arguments' do
    described_class.install(version_file: version_file, version_constant: 'VERSION')
    expect { Rake::Task['release:before_release'].invoke('invalid') }.to raise_error(ArgumentError, /invalid version/)
  end

  it 'runs successfully when no callbacks are registered' do
    described_class.install(version_file: version_file, version_constant: 'VERSION')
    expect do
      Rake::Task['release:before_release'].invoke('1.2.3')
      Rake::Task['release:after_bump'].invoke('1.2.3')
    end.not_to raise_error
  end

  it 'propagates after-bump failures' do
    described_class.install(version_file: version_file, version_constant: 'VERSION') do |release|
      release.after_bump { |**| raise 'bump callback failed' }
    end
    expect { Rake::Task['release:after_bump'].invoke('1.2.3') }.to raise_error('bump callback failed')
  end

  it 'rejects duplicate callback registration' do # rubocop:disable RSpec/ExampleLength -- Register two callbacks to exercise the error.
    expect do
      described_class.install(version_file: version_file, version_constant: 'VERSION') do |release|
        release.before_release { nil }
        release.before_release { nil }
      end
    end.to raise_error(ArgumentError, /already configured/)
  end
end
