# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'ruby-gem-release/rspec'

RSpec.describe 'Isolated release publication' do
  include RubyGemRelease::RSpec

  let(:gemspec) do
    <<~RUBY
      require_relative 'lib/example/version'
      Gem::Specification.new do |spec|
        spec.name = 'example'
        spec.version = VERSION
        spec.authors = ['Fixture']
        spec.summary = 'Release test fixture'
        spec.files = ['lib/example/version.rb', 'README.md']
      end
    RUBY
  end

  def prepare_project(project, builder: 'ProjectReleaseWorkflow.build')
    project.copy_files(path: File.expand_path('../../../examples/lifecycle_hooks', __dir__), files: %w[*.rb README.md])
    project.configure_workflow(require: 'release_workflow', builder: builder)
    project.write('example.gemspec', gemspec)
    project.write('lib/example/version.rb', "VERSION = '0.1.0'\n")
    project.write('CHANGELOG.md', "# Changelog\n\n## [Unreleased]\n\n- A change.\n")
    project.commit!
  end

  def artifacts(project)
    project.environment.fetch('RELEASE_DATA_DIR')
  end

  def published?(project)
    %w[registry hosting].map { |adapter| File.file?(File.join(artifacts(project), adapter, '0.2.0.gem')) }
  end

  def reject_branch_pushes(project)
    hook = File.join(project.remote, 'hooks', 'pre-receive')
    File.write(hook, "#!/bin/sh\nwhile read old new ref; do [ \"$ref\" = refs/heads/master ] && { echo 'protected branch' >&2; exit 1; }; done\nexit 0\n")
    File.chmod(0o755, hook)
    hook
  end

  it 'publishes the sealed release, then the next development commit, from a separate process' do
    with_release_project do |project|
      prepare_project(project)
      source = project.git('rev-parse', 'HEAD')

      project.isolated_release!(version: '0.2.0')

      expect(project.remote_file('v0.2.0', 'README.md')).to include('stable release of the project, 0.2.0')
      expect(project.remote_file('master', 'README.md')).to include('next release of the project, which should be 0.2.1')
      release = project.git('--git-dir', project.remote, 'rev-parse', 'v0.2.0^{commit}')
      expect(project.git('--git-dir', project.remote, 'rev-list', '--parents', '-n', '1', release).split.drop(1)).to eq([source])
      expect(project.git('--git-dir', project.remote, 'rev-list', '--parents', '-n', '1', 'master').split.drop(1)).to eq([release])
      archive = File.binread(File.join(artifacts(project), 'release.gem'))
      %w[registry hosting].each { |adapter| expect(File.binread(File.join(artifacts(project), adapter, '0.2.0.gem'))).to eq(archive) }
      expect(JSON.parse(File.read(File.join(artifacts(project), 'publication.json')))).to include('version' => '0.2.0', 'next_version' => '0.2.1', 'source_commit' => source)

      project.publish_isolated!
      expect(project.git('--git-dir', project.remote, 'rev-parse', 'v0.2.0^{commit}')).to eq(release)
    end
  end

  it 'fails before publishing the gem when the branch rejects the release commit, and resumes once permitted' do
    with_release_project do |project|
      prepare_project(project)
      hook = reject_branch_pushes(project)

      expect { project.isolated_release!(version: '0.2.0') }.to raise_error(RuntimeError, /protected branch/)
      expect(published?(project)).to eq([false, false])
      expect(project.git('--git-dir', project.remote, 'tag', '--list')).to eq('')

      File.delete(hook)
      project.publish_isolated!
      expect(published?(project)).to eq([true, true])
      expect(project.remote_file('master', 'README.md')).to include('which should be 0.2.1')
    end
  end

  it 'refuses publication when the default branch advanced after the build' do
    with_release_project do |project|
      prepare_project(project)
      %w[release:workflow:capture release:validate release:prepare release:workflow:resolve release:workflow:checkpoint release:workflow:seal].each { |task| project.run_task(task) }
      other = File.join(project.directory, 'other')
      project.git('clone', '--quiet', project.remote, other)
      project.git('-C', other, '-c', 'user.name=Other', '-c', 'user.email=other@example.com', 'commit', '--quiet', '--allow-empty', '-m', 'Concurrent change')
      project.git('-C', other, 'push', '--quiet', 'origin', 'master')

      expect { project.publish_isolated! }.to raise_error(RuntimeError, /Default branch advanced/)
      expect(published?(project)).to eq([false, false])
    end
  end

  it 'refuses a handoff that does not match the dispatched commit' do
    with_release_project do |project|
      prepare_project(project)
      %w[release:workflow:capture release:validate release:prepare release:workflow:resolve release:workflow:checkpoint release:workflow:seal].each { |task| project.run_task(task) }
      path = File.join(artifacts(project), 'publication.json')
      File.write(path, JSON.generate(JSON.parse(File.read(path)).merge('source_commit' => 'f' * 40)))

      expect { project.publish_isolated! }.to raise_error(RuntimeError, /not built from the dispatched commit/)
      expect(published?(project)).to eq([false, false])
    end
  end

  it 'rejects publication-stage hooks while sealing, before any publication' do
    with_release_project do |project|
      project.write('publication_hook.rb', <<~RUBY)
        require_relative 'release_workflow'
        module PublicationHookWorkflow
          def self.build(**)
            ProjectReleaseWorkflow.build(**).after(:publish_registry) { |_ctx| nil }
          end
        end
      RUBY
      prepare_project(project, builder: 'PublicationHookWorkflow.build')
      project.configure_workflow(require: 'publication_hook', builder: 'PublicationHookWorkflow.build')
      project.commit!('Use a publication hook')

      expect { project.isolated_release!(version: '0.2.0') }.to raise_error(RuntimeError, /runs no project hooks for publish_registry/)
      expect(File).not_to exist(File.join(artifacts(project), 'publication.json'))
    end
  end
end
