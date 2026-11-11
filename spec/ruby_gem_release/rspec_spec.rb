# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/rspec'

RSpec.describe RubyGemRelease::RSpec do
  include described_class

  it 'isolates the fixture from inherited release and Git state and cleans up on failure' do
    directory = nil
    original = ENV.to_h
    ENV.update('GITHUB_ACTIONS' => 'true', 'RUNNER_TEMP' => '/outer/runner', 'RELEASE_STATE_FILE' => '/outer/state',
               'GIT_DIR' => '/outer/git', 'RUBYGEMS_API_KEY' => 'outer-key')
    expect do
      with_release_project do |project|
        directory = project.directory
        expect(project.environment.keys).not_to include('GITHUB_ACTIONS', 'RUNNER_TEMP', 'RELEASE_STATE_FILE', 'GIT_DIR', 'RUBYGEMS_API_KEY')
        expect(project.git('remote', 'get-url', 'origin')).to eq(project.remote)
        raise 'Fixture failure'
      end
    end.to raise_error('Fixture failure')
    expect(File).not_to exist(directory)
  ensure
    ENV.replace(original)
  end

  it 'keeps fixture files inside the checkout and reports failed Git commands' do
    with_release_project do |project|
      expect { project.write('../escape', 'no') }.to raise_error(ArgumentError, /inside the checkout/)
      expect { project.git('show', 'missing') }.to raise_error(RuntimeError, /missing/)
    end
  end

  it 'transports exported values and failed steps between separate Rake processes' do
    with_release_project do |project|
      project.write('Rakefile', <<~RUBY)
        require 'ruby-gem-release/rspec'
        task(:export) { RubyGemRelease::RSpec::Provider.new.export('FIXTURE_VALUE' => 'exported') }
        task(:check) { raise 'export lost' unless ENV.fetch('FIXTURE_VALUE') == 'exported' }
        task(:reject) { raise 'Rejected fixture task' }
        task(:failure) { puts RubyGemRelease::RSpec::Provider.new.failed_steps }
      RUBY
      project.run_task('export')
      project.run_task('check')
      expect { project.run_task('reject') }.to raise_error(RuntimeError, /Rejected fixture task/)
      expect(project.run_task('failure')).to include('reject')
    end
  end

  [RubyGemRelease::RSpec::Destination, RubyGemRelease::RSpec::Hosting].each do |adapter|
    context "with #{adapter}" do
      let(:release) { RubyGemRelease::Release.new(version: '0.1.0', gemspec_version: '0.1.0', date: Date.new(2026, 11, 11)) }

      it 'stores an exact archive locally, accepts repetition, and rejects checksum conflicts' do
        with_release_project do |project|
          artifact = File.join(project.directory, 'example.gem')
          File.write(artifact, 'release archive')
          package = instance_double(RubyGemRelease::Package::RubyGem, artifact: artifact)
          publication = adapter.new(directory: project.directory)
          expect(publication.published?(release, package: package)).to be(false)
          2.times { publication.publish!(release, package: package) }
          expect(publication.published?(release, package: package)).to be(true)
          File.write(artifact, 'different archive')
          expect { publication.publish!(release, package: package) }.to raise_error(RuntimeError, /checksum differs/)
        end
      end

      it 'can reject publication without recording success' do
        with_release_project do |project|
          artifact = File.join(project.directory, 'example.gem')
          File.write(artifact, 'release archive')
          package = instance_double(RubyGemRelease::Package::RubyGem, artifact: artifact)
          publication = adapter.new(directory: project.directory, failure: 'Rejected test publication')
          expect { publication.publish!(release, package: package) }.to raise_error(RuntimeError, /Rejected test publication/)
          expect(publication.published?(release, package: package)).to be(false)
        end
      end
    end
  end
end
