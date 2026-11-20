# frozen_string_literal: true

require 'spec_helper'
require 'ruby-gem-release/rspec'
require 'rubygems/package'
require 'tmpdir'

RSpec.describe 'Plain text version release integration' do
  include RubyGemRelease::RSpec

  def gemspec_version(project, ref)
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, 'VERSION'), project.remote_file(ref, 'VERSION'))
      path = File.join(directory, 'example.gemspec')
      File.write(path, project.remote_file(ref, 'example.gemspec'))
      Gem::Specification.load(path).version.to_s
    end
  end

  it 'releases and bumps a gem whose gemspec reads a plain text VERSION file, updating references' do
    with_release_project do |project|
      project.environment['RELEASE_TEST_LIB'] = ENV.fetch('RELEASE_CONSUMER_LIB', File.expand_path('lib'))
      project.write('Rakefile', <<~RUBY)
        require 'ruby-gem-release/workflow/ruby_gem'
        require 'ruby-gem-release/version/plain_text'
        require 'ruby-gem-release/version/references'
        require 'ruby-gem-release/rspec'

        loaded = $LOADED_FEATURES.find { |path| path.end_with?('/ruby-gem-release/version/plain_text.rb') }
        expected = File.join(ENV.fetch('RELEASE_TEST_LIB'), 'ruby-gem-release/version/plain_text.rb')
        raise 'Consumer loaded the wrong release library' unless loaded && File.realpath(loaded) == File.realpath(expected)

        RubyGemRelease::Workflow::RubyGem.new(
          version: RubyGemRelease::Version::References.new(
            version: RubyGemRelease::Version::PlainText.new,
            references: { 'README.md' => [/version: (?<version>\\d+\\.\\d+\\.\\d+)/] }
          ),
          changelog: nil,
          provider: RubyGemRelease::RSpec::Provider.new,
          destination: RubyGemRelease::RSpec::Destination.new,
          hosting: RubyGemRelease::RSpec::Hosting.new
        ).install_tasks
      RUBY
      project.write('VERSION', "0.1.0\n")
      project.write('README.md', "version: 0.1.0\n")
      project.write('lib/example.rb', "module Example; end\n")
      project.write('example.gemspec', <<~RUBY)
        Gem::Specification.new do |gem|
          gem.name = 'example'
          gem.version = File.read(File.join(__dir__, 'VERSION')).strip
          gem.summary = 'Plain text version fixture'
          gem.authors = ['Example']
          gem.files = %w[VERSION lib/example.rb]
        end
      RUBY
      project.commit!

      project.release!(version: '0.2.0')

      expect(project.remote_file('v0.2.0', 'VERSION')).to eq('0.2.0')
      expect(gemspec_version(project, 'v0.2.0')).to eq('0.2.0')
      expect(project.remote_file('v0.2.0', 'README.md')).to eq('version: 0.1.0')
      expect(project.remote_file('master', 'VERSION')).to eq('0.2.1')
      expect(project.remote_file('master', 'README.md')).to eq('version: 0.2.0')
      artifacts = project.environment.fetch('RELEASE_DATA_DIR')
      archive = File.join(artifacts, 'release.gem')
      expect(Gem::Package.new(archive).spec.version.to_s).to eq('0.2.0')
      %w[registry hosting].each do |adapter|
        expect(File.binread(File.join(artifacts, adapter, '0.2.0.gem'))).to eq(File.binread(archive))
      end
      project.run_task('release:bump')
      expect(project.remote_file('master', 'VERSION')).to eq('0.2.1')
      expect(project.remote_file('master', 'README.md')).to eq('version: 0.2.0')
      expect(project.git('status', '--porcelain')).to eq('')
    end
  end
end
