# frozen_string_literal: true

require 'rspec'
require 'ruby-gem-release/rspec'

RSpec.describe 'Project release customizations' do
  include RubyGemRelease::RSpec

  it 'updates README in the release and next development commits' do
    with_release_project do |project|
      project.copy_files(path: File.expand_path('..', __dir__), files: %w[release_notes.rb release_workflow.rb README.md])
      project.configure_workflow(require: 'release_workflow', builder: 'ProjectReleaseWorkflow.build')
      project.write('example.gemspec', <<~RUBY)
        require_relative 'lib/example/version'
        Gem::Specification.new do |spec|
          spec.name = 'example'
          spec.version = VERSION
          spec.authors = ['Fixture']
          spec.summary = 'Release test fixture'
          spec.files = ['lib/example/version.rb', 'README.md']
        end
      RUBY
      project.write('lib/example/version.rb', "VERSION = '0.1.0'\n")
      project.write('CHANGELOG.md', "# Changelog\n\n## [Unreleased]\n\n- A change.\n")
      project.commit!

      project.release!(version: '0.2.0')

      expect(project.remote_file('v0.2.0', 'README.md')).to include('stable release of the project, 0.2.0')
      expect(project.remote_file('master', 'README.md')).to include('next release of the project, which should be 0.2.1')
      artifacts = project.environment.fetch('RELEASE_DATA_DIR')
      archive = File.binread(File.join(artifacts, 'release.gem'))
      %w[registry hosting].each do |adapter|
        expect(File.binread(File.join(artifacts, adapter, '0.2.0.gem'))).to eq(archive)
      end
      expect(project.git('status', '--porcelain')).to eq('')
    end
  end
end
