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

  it 'loads a literal workflow path and installs the project builder with local adapters' do
    with_release_project do |project|
      source = "release-\"\#{raise 'Unexpected interpolation'}"
      project.write("#{source}.rb", <<~RUBY)
        module FixtureBuilders
          module Release
            def self.workflow(provider:, destination:, hosting:)
              raise 'Destination is not local' unless destination.is_a?(RubyGemRelease::RSpec::Destination)
              raise 'Hosting is not local' unless hosting.is_a?(RubyGemRelease::RSpec::Hosting)

              @provider = provider
              self
            end

            def self.install_tasks
              Rake::Task.define_task(:configured_hook) do
                @provider.export('PROJECT_HOOK' => 'ran')
              end
            end
          end
        end
      RUBY

      project.configure_workflow(require: "#{source}.rb", builder: '::FixtureBuilders::Release.workflow')
      project.run_task('configured_hook')

      expect(project.environment.fetch('PROJECT_HOOK')).to eq('ran')
    end
  end

  it 'rejects builder expressions before replacing a custom Rakefile' do
    with_release_project do |project|
      project.write('Rakefile', 'Custom setup')
      [nil, :workflow, '', 'Release', 'release.workflow', 'Release.workflow()', "Release.workflow\nraise 'Injected'"].each do |builder|
        expect { project.configure_workflow(require: 'release', builder: builder) }.to raise_error(ArgumentError, /builder/)
      end
      expect(File.read(File.join(project.checkout, 'Rakefile'))).to eq('Custom setup')
    end
  end

  it 'rejects invalid workflow paths and links that escape the checkout without changing files' do
    with_release_project do |project|
      project.write('Rakefile', 'Custom setup')
      outside = File.join(project.directory, 'outside.rb')
      File.write(outside, 'Do not load.')
      File.symlink(outside, File.join(project.checkout, 'release.rb'))

      [nil, :release, '', '../outside', outside, '.git/config', 'release', 'release.rb', "release\0"].each do |source|
        expect { project.configure_workflow(require: source, builder: 'Release.workflow') }.to raise_error(ArgumentError)
      end
      expect(File.read(File.join(project.checkout, 'Rakefile'))).to eq('Custom setup')

      File.unlink(File.join(project.checkout, 'Rakefile'))
      File.symlink(outside, File.join(project.checkout, 'Rakefile'))
      project.write('workflow.rb', 'Project builder source')
      expect { project.configure_workflow(require: 'workflow', builder: 'Release.workflow') }.to raise_error(ArgumentError, /stay inside/)
      expect(File.read(outside)).to eq('Do not load.')
    end
  end

  it 'copies explicit fixture files with relative paths, binary content, and file modes' do
    with_release_project do |project|
      root = File.join(project.directory, 'source')
      FileUtils.mkdir_p(File.join(root, 'tasks'))
      File.binwrite(File.join(root, 'README.md'), "Project\n")
      File.binwrite(File.join(root, 'tasks/release.rb'), "\x00\xFF")
      File.chmod(0o751, File.join(root, 'tasks/release.rb'))
      File.write(File.join(root, 'ignored'), 'Do not copy.')

      project.copy_files(path: root, files: 'README.md')
      2.times { project.copy_files(path: root, files: %w[README.md tasks/release.rb]) }

      expect(File.binread(File.join(project.checkout, 'README.md'))).to eq("Project\n")
      expect(File.binread(File.join(project.checkout, 'tasks/release.rb'))).to eq("\x00\xFF".b)
      expect(File.stat(File.join(project.checkout, 'tasks/release.rb')).mode & 0o777).to eq(0o751)
      expect(File).not_to exist(File.join(project.checkout, 'ignored'))
    end
  end

  it 'copies recursive glob matches with brace alternatives, hidden files, and preserved modes' do
    with_release_project do |project|
      root = File.join(project.directory, 'source')
      FileUtils.mkdir_p(%w[lib/nested .config .git nested directory.md].map { |path| File.join(root, path) })
      %w[README.md lib/nested/notes.md .hidden.md .config/settings.md].each { |path| File.write(File.join(root, path), path) }
      File.binwrite(File.join(root, 'lib/main.js'), "\x00\xFF")
      File.chmod(0o751, File.join(root, 'lib/main.js'))
      File.write(File.join(root, 'ignored.rb'), 'Do not copy.')
      File.write(File.join(root, '.git/private.md'), 'Do not copy Git metadata.')
      File.write(File.join(root, 'nested/.git'), 'Do not copy worktree metadata.')
      original_config = File.read(File.join(project.checkout, '.git/config'))

      project.copy_files(path: root, files: './**/*.{js,md}')

      %w[README.md lib/nested/notes.md .hidden.md .config/settings.md].each do |path|
        expect(File.read(File.join(project.checkout, path))).to eq(path)
      end
      expect(File.binread(File.join(project.checkout, 'lib/main.js'))).to eq("\x00\xFF".b)
      expect(File.stat(File.join(project.checkout, 'lib/main.js')).mode & 0o777).to eq(0o751)
      expect(File).not_to exist(File.join(project.checkout, 'ignored.rb'))
      expect(File).not_to exist(File.join(project.checkout, 'directory.md'))
      expect(File).not_to exist(File.join(project.checkout, '.git/private.md'))
      expect(File).not_to exist(File.join(project.checkout, 'nested/.git'))
      expect(File.read(File.join(project.checkout, '.git/config'))).to eq(original_config)
    end
  end

  it 'combines and deduplicates literal paths and globs while preferring existing exact paths' do
    with_release_project do |project|
      root = File.join(project.directory, 'source')
      FileUtils.mkdir_p(%w[lib bin].map { |path| File.join(root, path) })
      %w[bin/run lib/a.rb lib/b.rb lib/aa.rb [notes].md n.md].each { |path| File.write(File.join(root, path), path) }
      allow(FileUtils).to receive(:copy_file).and_call_original

      project.copy_files(path: root, files: ['bin/run', 'lib/[ab].rb', 'lib/?.rb', './lib/a.rb', '[notes].md'])

      expect(FileUtils).to have_received(:copy_file).with(File.realpath(File.join(root, 'lib/a.rb')), File.join(File.realpath(project.checkout), 'lib/a.rb'), true).once
      %w[bin/run lib/a.rb lib/b.rb [notes].md].each do |path|
        expect(File.read(File.join(project.checkout, path))).to eq(path)
      end
      expect(File).not_to exist(File.join(project.checkout, 'lib/aa.rb'))
      expect(File).not_to exist(File.join(project.checkout, 'n.md'))
    end
  end

  it 'does not traverse symbolic-link directories when expanding recursive globs' do
    with_release_project do |project|
      root = File.join(project.directory, 'source')
      FileUtils.mkdir_p(File.join(root, 'lib'))
      File.write(File.join(root, 'lib/release.rb'), 'Project workflow')
      File.symlink(File.join(root, 'lib'), File.join(root, 'alias'))

      expect { project.copy_files(path: root, files: 'alias/*.rb') }.to raise_error(ArgumentError, /regular file/)
      project.copy_files(path: root, files: '**/*.rb')

      expect(File.read(File.join(project.checkout, 'lib/release.rb'))).to eq('Project workflow')
      expect(File).not_to exist(File.join(project.checkout, 'alias'))
    end
  end

  it 'copies all files recursively by default, including hidden files but not Git metadata' do
    with_release_project do |project|
      root = File.join(project.directory, 'source')
      FileUtils.mkdir_p(%w[tasks .config .git nested].map { |path| File.join(root, path) })
      File.write(File.join(root, 'README.md'), 'Project')
      File.binwrite(File.join(root, 'tasks/release.rb'), "\x00\xFF")
      File.chmod(0o751, File.join(root, 'tasks/release.rb'))
      File.write(File.join(root, '.hidden'), 'Hidden file')
      File.write(File.join(root, '.config/settings'), 'Hidden directory')
      File.write(File.join(root, '.git/config'), 'Do not copy repository metadata.')
      File.write(File.join(root, 'nested/.git'), 'Do not copy worktree metadata.')
      original_config = File.read(File.join(project.checkout, '.git/config'))

      project.copy_files(path: root, files: [])
      expect(Dir.children(project.checkout)).to eq(['.git'])
      project.copy_files(path: root)
      project.copy_files(path: root, files: '**/*')

      expect(File.read(File.join(project.checkout, 'README.md'))).to eq('Project')
      expect(File.binread(File.join(project.checkout, 'tasks/release.rb'))).to eq("\x00\xFF".b)
      expect(File.stat(File.join(project.checkout, 'tasks/release.rb')).mode & 0o777).to eq(0o751)
      expect(File.read(File.join(project.checkout, '.hidden'))).to eq('Hidden file')
      expect(File.read(File.join(project.checkout, '.config/settings'))).to eq('Hidden directory')
      expect(File.read(File.join(project.checkout, '.git/config'))).to eq(original_config)
      expect(File).not_to exist(File.join(project.checkout, 'nested/.git'))
      expect(project.git('remote', 'get-url', 'origin')).to eq(project.remote)
    end
  end

  it 'rejects missing files and directories before copying any files' do
    with_release_project do |project|
      root = File.join(project.directory, 'source')
      FileUtils.mkdir_p(File.join(root, 'tasks/empty.rb'))
      File.write(File.join(root, 'README.md'), 'Project')

      %w[missing tasks missing/**/*.rb *.txt **/*.rb].each do |invalid|
        expect { project.copy_files(path: root, files: ['README.md', invalid]) }.to raise_error(ArgumentError, /regular file/)
        expect(File).not_to exist(File.join(project.checkout, 'README.md'))
      end
    end
  end

  it 'rejects absolute paths and paths outside the source root' do
    with_release_project do |project|
      root = File.join(project.directory, 'source')
      FileUtils.mkdir_p(root)
      File.write(File.join(project.directory, 'outside'), 'Keep.')

      ['../outside', '../*', File.join(project.directory, 'outside'), File.join(project.directory, '*')].each do |invalid|
        expect { project.copy_files(path: root, files: [invalid]) }.to raise_error(ArgumentError, /relative files inside their root/)
      end
      expect(File.read(File.join(project.directory, 'outside'))).to eq('Keep.')
    end
  end

  it 'rejects source and destination symbolic links outside their roots' do
    with_release_project do |project|
      root = File.join(project.directory, 'source')
      FileUtils.mkdir_p(File.join(root, 'tasks'))
      outside = File.join(project.directory, 'outside')
      FileUtils.mkdir_p(outside)
      File.write(File.join(outside, 'release.rb'), 'Keep.')
      File.symlink(File.join(outside, 'release.rb'), File.join(root, 'linked.rb'))
      expect { project.copy_files(path: root, files: ['linked.rb']) }.to raise_error(ArgumentError, /stay inside/)
      expect { project.copy_files(path: root) }.to raise_error(ArgumentError, /stay inside/)
      expect { project.copy_files(path: root, files: '*.rb') }.to raise_error(ArgumentError, /stay inside/)
      File.symlink(outside, File.join(root, 'linked'))
      expect { project.copy_files(path: root, files: 'linked/*.rb') }.to raise_error(ArgumentError, /stay inside/)

      File.write(File.join(root, 'tasks/release.rb'), 'Replace.')
      File.symlink(outside, File.join(project.checkout, 'tasks'))
      expect { project.copy_files(path: root, files: ['tasks/release.rb']) }.to raise_error(ArgumentError, /stay inside/)
      expect { project.copy_files(path: root, files: 'tasks/*.rb') }.to raise_error(ArgumentError, /stay inside/)
      File.symlink(File.join(outside, 'release.rb'), File.join(project.checkout, 'release.rb'))
      File.write(File.join(root, 'release.rb'), 'Replace.')
      expect { project.copy_files(path: root, files: ['release.rb']) }.to raise_error(ArgumentError, /stay inside/)
      expect(File.read(File.join(outside, 'release.rb'))).to eq('Keep.')
    end
  end

  it 'rejects explicit Git metadata and destination aliases to it' do
    with_release_project do |project|
      root = File.join(project.directory, 'source')
      FileUtils.mkdir_p(File.join(root, '.git'))
      File.write(File.join(root, '.git/config'), 'Do not copy.')
      File.write(File.join(root, 'config'), 'Do not replace.')
      original_config = File.read(File.join(project.checkout, '.git/config'))

      %w[.git/config .git/* **/.git/*].each do |invalid|
        expect { project.copy_files(path: root, files: [invalid]) }.to raise_error(ArgumentError, /Git metadata/)
      end
      File.symlink(File.join(project.checkout, '.git/config'), File.join(project.checkout, 'config'))
      expect { project.copy_files(path: root, files: ['config']) }.to raise_error(ArgumentError, /Git metadata/)
      expect { project.copy_files(path: root, files: 'con*') }.to raise_error(ArgumentError, /Git metadata/)
      expect(File.read(File.join(project.checkout, '.git/config'))).to eq(original_config)
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
