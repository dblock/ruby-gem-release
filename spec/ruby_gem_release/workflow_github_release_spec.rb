# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'open3'
require 'tmpdir'
require 'rubygems/package'

RSpec.describe 'Workflow release lifecycle' do
  let(:directory) { Dir.mktmpdir }
  let(:checkout) { File.join(directory, 'checkout') }
  let(:remote) { File.join(directory, 'remote.git') }
  let(:workflow) { YAML.load_file('.github/workflows/release.yml') }
  let(:environment) do
    {
      'BUNDLE_GEMFILE' => ENV.fetch('RELEASE_CONSUMER_GEMFILE', File.expand_path('Gemfile')),
      'RUBYLIB' => ENV.fetch('RELEASE_CONSUMER_LIB', File.expand_path('lib')),
      'RELEASE_TEST_LIB' => ENV.fetch('RELEASE_CONSUMER_LIB', File.expand_path('lib')),
      'GEM_HOME' => ENV.fetch('RELEASE_CONSUMER_GEM_HOME', Gem.dir),
      'GEM_PATH' => ENV.fetch('RELEASE_CONSUMER_GEM_PATH', Gem.path.join(File::PATH_SEPARATOR)),
      'RUNNER_TEMP' => directory,
      'GITHUB_ENV' => File.join(directory, 'environment'),
      'GITHUB_OUTPUT' => File.join(directory, 'output'),
      'GITHUB_STEP_SUMMARY' => File.join(directory, 'summary'),
      'GITHUB_REPOSITORY' => 'owner/example',
      'DEFAULT_BRANCH' => 'master',
      'GITHUB_REF' => 'refs/heads/master',
      'INPUT_VERSION' => '',
      'INPUT_GEMSPEC' => '',
      'GIT_USER_NAME' => 'Fixture',
      'GIT_USER_EMAIL' => 'fixture@example.com',
      'RUBYGEMS_OWNER' => '',
      'TZ' => inputs.fetch('timezone').fetch('default'),
      'RELEASE_TEST_REMOTE' => remote
    }
  end

  def consumer_rakefile
    File.read('examples/keep_a_changelog/Rakefile').sub(
      "  changelog: RubyGemRelease::Changelog::KeepAChangelog.new\n",
      "  changelog: RubyGemRelease::Changelog::KeepAChangelog.new,\n  " \
      "success: #{result_callback('success')},\n  " \
      "failure: #{result_callback('failure')}\n"
    )
  end

  def result_callback(name)
    if name == 'success'
      "->(release) { File.write(File.join(ENV.fetch('RUNNER_TEMP'), 'success.json'), JSON.generate([release.version, release.previous_version])) }"
    else
      "->(failure) { File.write(File.join(ENV.fetch('RUNNER_TEMP'), 'failure.json'), JSON.generate([failure.release&.version, failure.phase, failure.error&.message])) }"
    end
  end

  def consumer_changelog
    File.read('examples/keep_a_changelog/CHANGELOG.md')
  end

  def consumer_ignores
    ''
  end

  before do
    FileUtils.mkdir_p(File.join(checkout, 'lib/example'))
    File.write(environment.fetch('GITHUB_ENV'), '')
    File.write(environment.fetch('GITHUB_OUTPUT'), '')
    File.write(File.join(checkout, 'lib/example/version.rb'), "module Example\n  VERSION = '0.1.0'\nend\n")
    File.write(File.join(checkout, 'example.gemspec'), <<~RUBY)
      require_relative 'lib/example/version'
      Gem::Specification.new do |spec|
        spec.name = 'example'
        spec.version = Example::VERSION
        spec.authors = ['Fixture']
        spec.summary = 'Release fixture'
        spec.files = ['lib/example/version.rb']
      end
    RUBY
    File.write(File.join(checkout, 'CHANGELOG.md'), consumer_changelog)
    File.write(File.join(checkout, 'Rakefile'), "#{consumer_rakefile}\n#{publication_stub}")
    File.write(File.join(checkout, '.gitignore'), consumer_ignores)
    run_git('init', '--bare', '--quiet', '-b', 'master', remote)
    run_git('init', '--quiet', '-b', 'master', checkout)
    run_git('-C', checkout, 'add', '.')
    run_git('-C', checkout, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'commit', '--quiet', '-m', 'Initial')
    run_git('-C', checkout, 'remote', 'add', 'origin', remote)
    run_git('-C', checkout, 'push', '--quiet', '-u', 'origin', 'master')
  end

  after { FileUtils.remove_entry(directory) }

  def publication_stub
    <<~RUBY
      loaded = $LOADED_FEATURES.find { |path| path.end_with?('/ruby-gem-release/tasks.rb') }
      expected = File.join(ENV.fetch('RELEASE_TEST_LIB'), 'ruby-gem-release/tasks.rb')
      raise 'Consumer loaded the wrong release library: ' + loaded.to_s unless loaded && File.realpath(loaded) == File.realpath(expected)
      module StubPublication
        def capture3(*command)
          upload = command[0, 4] == [Gem.ruby, '-S', 'gem', 'push']
          return super unless upload || command.first == 'gh'

          tags, = super('git', '--git-dir', ENV.fetch('RELEASE_TEST_REMOTE'), 'tag')
          raise 'Tag pushed before package publication' if upload && !tags.empty?
          version = ENV.fetch('INPUT_VERSION', '')
          version = '0.1.0' if version.empty?
          raise 'GitHub Release attempted before tag push' if !upload && tags.strip != 'v' + version
          File.open(File.join(ENV.fetch('RUNNER_TEMP'), 'publication.jsonl'), 'a') do |file|
            file.puts JSON.generate(command)
          end
          status = Object.new
          status.define_singleton_method(:success?) { true }
          ['published', '', status]
        end
      end
      Open3.singleton_class.prepend(StubPublication)
      module StubVersionLookup
        def start(host, port, **options)
          return super unless host == 'rubygems.org'

          raise 'Unexpected RubyGems request configuration' unless port == 443 && options == {use_ssl: true, open_timeout: 10, read_timeout: 30, max_retries: 0}
          http = Object.new
          http.define_singleton_method(:get) do |path|
            version = ENV.fetch('INPUT_VERSION', '')
            version = '0.1.0' if version.empty?
            raise 'Unexpected version lookup: ' + path unless path == '/api/v2/rubygems/example/versions/' + version + '.json'
            File.open(File.join(ENV.fetch('RUNNER_TEMP'), 'version-lookups.jsonl'), 'a') { |file| file.puts JSON.generate(path) }
            Struct.new(:code).new(ENV.fetch('RELEASE_TEST_VERSION_STATUS', '404'))
          end
          yield http
        end
      end
      Net::HTTP.singleton_class.prepend(StubVersionLookup)
    RUBY
  end

  def run_git(*arguments)
    output, error, status = Open3.capture3('git', *arguments)
    raise error unless status.success?

    output.strip
  end

  def phase_command(name)
    step = steps.find { |item| item['name'] == name }
    return step.fetch('run') if name == 'Validate Release'

    command_input = step.dig('env', 'COMMAND')
    command_input ? inputs.fetch(command_input[/inputs\.(\w+)/, 1]).fetch('default') : step.fetch('run')
  end

  def validation_command
    environment.fetch('RELEASE_TEST_VALIDATION_COMMAND', inputs.fetch('validate').fetch('default'))
  end

  def validation_decision
    File.readlines(environment.fetch('GITHUB_OUTPUT'), chomp: true).grep(/\Aproceed=/).last&.delete_prefix('proceed=')
  end

  def steps
    workflow.fetch('jobs').fetch('release').fetch('steps')
  end

  def inputs
    workflow.fetch(true).fetch('workflow_call').fetch('inputs')
  end

  def run_phase(name)
    return if skipped_phase?(name)

    output, error, status = Open3.capture3(phase_environment(name), 'bash', '-euo', 'pipefail', '-c', phase_command(name), chdir: checkout)
    raise "#{output}\n#{error}" unless status.success?

    File.readlines(environment.fetch('GITHUB_ENV'), chomp: true).each do |line|
      key, value = line.split('=', 2)
      environment[key] = value
    end
  end

  def skipped_phase?(name)
    step = steps.find { |item| item['name'] == name }
    step['if']&.include?("steps.validate_release.outputs.proceed == 'true'") && validation_decision != 'true'
  end

  def phase_environment(name)
    name == 'Validate Release' ? environment.merge('COMMAND' => validation_command) : environment
  end

  def generate_bundler_artifacts
    FileUtils.mkdir_p(File.join(checkout, '.bundle'))
    FileUtils.mkdir_p(File.join(checkout, 'vendor/bundle/ruby/gems'))
    File.write(File.join(checkout, '.bundle/config'), "BUNDLE_PATH: vendor/bundle\n")
    File.write(File.join(checkout, 'vendor/bundle/ruby/gems/generated.rb'), 'dependency')
  end

  shared_examples 'clean release preparation' do
    it 'checks the checkout after dependency setup and before preparation', :aggregate_failures do
      setup = steps.index { |item| item['uses'] == 'ruby/setup-ruby@v1' }
      capture = steps.index { |item| item['name'] == 'Capture Release Context' }
      prepare = steps.index { |item| item['name'] == 'Prepare Release' }
      expect(capture).to be > setup
      expect(capture).to be < prepare
    end

    it 'rejects generated Bundler files before changing the version or changelog', :aggregate_failures do
      generate_bundler_artifacts
      original = File.read(File.join(checkout, 'lib/example/version.rb'))
      expect do
        run_phase('Capture Release Context')
        run_phase('Validate Release')
        run_phase('Prepare Release')
      end.to raise_error(%r{clean checkout.*\n.*\.bundle/config.*\n.*vendor/bundle}m)
      expect(File.read(File.join(checkout, 'lib/example/version.rb'))).to eq(original)
      expect(File.read(File.join(checkout, 'CHANGELOG.md'))).to eq(consumer_changelog)
      expect(run_git('-C', checkout, 'diff', '--cached', '--name-only')).to eq('')
      expect(run_git('--git-dir', remote, 'tag')).to eq('')
      expect(File).not_to exist(File.join(directory, 'publication.jsonl'))
    end

    it 'refuses generated Bundler files created after preparation without staging them', :aggregate_failures do
      run_phase('Capture Release Context')
      run_phase('Validate Release')
      run_phase('Prepare Release')
      run_phase('Resolve Prepared Version')
      initial = run_git('-C', checkout, 'rev-parse', 'HEAD')
      generate_bundler_artifacts
      expect { run_phase('Publish Release') }.to raise_error(/commit refused/)
      expect(run_git('-C', checkout, 'diff', '--cached', '--name-only')).to eq('CHANGELOG.md')
      expect(run_git('-C', checkout, 'rev-parse', 'HEAD')).to eq(initial)
      expect(run_git('-C', checkout, 'tag')).to eq('')
      expect(File).not_to exist(File.join(directory, 'publication.jsonl'))
    end

    it 'rejects a published version before validation, committing, building, tagging, or uploading', :aggregate_failures do
      initial = run_git('-C', checkout, 'rev-parse', 'HEAD')
      run_phase('Capture Release Context')
      run_phase('Validate Release')
      run_phase('Prepare Release')
      environment['RELEASE_TEST_VERSION_STATUS'] = '200'
      expect { run_phase('Resolve Prepared Version') }.to raise_error(/example 0.1.0.*already published.*recovery/)
      expect(environment).not_to have_key('RELEASE_VERSION')
      expect(run_git('-C', checkout, 'rev-parse', 'HEAD')).to eq(initial)
      expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(initial)
      expect(run_git('-C', checkout, 'tag')).to eq('')
      expect(File).not_to exist(File.join(directory, 'release.gem'))
      expect(File).not_to exist(File.join(directory, 'publication.jsonl'))
    end

    it 'rechecks RubyGems before committing when the version appears after validation', :aggregate_failures do
      run_phase('Capture Release Context')
      run_phase('Validate Release')
      run_phase('Prepare Release')
      run_phase('Resolve Prepared Version')
      initial = run_git('-C', checkout, 'rev-parse', 'HEAD')
      environment['RELEASE_TEST_VERSION_STATUS'] = '200'
      expect { run_phase('Publish Release') }.to raise_error(/already published/)
      expect(run_git('-C', checkout, 'rev-parse', 'HEAD')).to eq(initial)
      expect(run_git('--git-dir', remote, 'tag')).to eq('')
      expect(run_git('-C', checkout, 'tag')).to eq('')
      expect(File).not_to exist(File.join(directory, 'release.gem'))
      expect(File).not_to exist(File.join(directory, 'publication.jsonl'))
    end

    context 'with intentionally ignored Bundler output' do
      def consumer_ignores
        ".bundle/\nvendor/bundle/\n"
      end

      before { generate_bundler_artifacts }

      it_behaves_like 'a local release lifecycle'
    end

    context 'with a custom preparation command' do
      def phase_command(name)
        command = super
        name == 'Prepare Release' ? "#{command}\nprintf 'Custom release documentation' > README.md" : command
      end

      it 'retains custom command outputs in the intended preparation index' do
        run_phase('Capture Release Context')
        run_phase('Validate Release')
        run_phase('Prepare Release')
        run_phase('Resolve Prepared Version')
        expect(run_git('-C', checkout, 'diff', '--cached', '--name-only').lines.map(&:strip)).to contain_exactly('CHANGELOG.md', 'README.md')
      end
    end
  end

  shared_examples 'a local release lifecycle' do |next_heading = '## [Unreleased]'|
    it 'runs the documented callbacks with real Git pushes and isolated package and hosting publication', :aggregate_failures do
      run_phase('Configure Release Inputs') if steps.any? { |item| item['name'] == 'Configure Release Inputs' }
      run_phase('Enable Release Failure Callback')
      run_phase('Capture Release Context')
      run_phase('Validate Release')
      expect(validation_decision).to eq('true')
      run_phase('Prepare Release')
      run_phase('Resolve Prepared Version')
      run_phase('Publish Release')
      release_commit = run_git('-C', checkout, 'rev-parse', 'HEAD')
      expect(run_git('-C', checkout, 'rev-parse', 'v0.1.0')).to eq(release_commit)
      offset = environment.fetch('TZ') == 'UTC' ? /\+0000\z/ : /-0[45]00\z/
      expect(run_git('-C', checkout, 'log', '-1', '--format=%ai')).to match(offset)
      expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(release_commit)
      expect(run_git('--git-dir', remote, 'rev-parse', 'v0.1.0')).to eq(release_commit)
      expect(Gem::Package.new(File.join(directory, 'release.gem')).spec.version.to_s).to eq('0.1.0')
      expect(File).to exist(File.join(directory, 'release.bundle'))
      run_phase('Prepare Next Development Iteration')
      run_phase('Run Release Success Callback')
      expect(JSON.parse(File.read(File.join(directory, 'success.json')))).to eq(%w[0.1.0 0.1.0])
      expect(run_git('-C', checkout, 'log', '-1', '--format=%s')).to eq('Prepare next development iteration, 0.1.1')
      expect(File.read(File.join(checkout, 'lib/example/version.rb'))).to include("VERSION = '0.1.1'")
      expect(File.read(File.join(checkout, 'CHANGELOG.md'))).to include(next_heading)
      expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(run_git('-C', checkout, 'rev-parse', 'HEAD'))
      expect(run_git('--git-dir', remote, 'rev-parse', 'v0.1.0')).to eq(release_commit)
      expect(run_git('-C', checkout, 'status', '--porcelain')).to eq('')
      expect(run_git('-C', checkout, 'ls-files', '.bundle', 'vendor/bundle')).to eq('')
      artifact = File.join(directory, 'example-0.1.0.gem')
      publications = File.readlines(File.join(directory, 'publication.jsonl')).map { |line| JSON.parse(line) }
      expect(publications).to eq([
                                   [Gem.ruby, '-S', 'gem', 'push', artifact],
                                   ['gh', 'release', 'create', 'v0.1.0', '--repo', 'owner/example', '--verify-tag',
                                    '--title', 'v0.1.0', '--generate-notes', artifact]
                                 ])
    end
  end

  shared_examples 'release validation control' do
    it 'places the release decision before edits and gates all downstream release steps' do
      validation = steps.find { |step| step['id'] == 'validate_release' }
      downstream = %w[prepare_release resolve_prepared_version test_release authenticate_rubygems authenticate_pending_publisher
                      publish_release preserve_release_artifacts prepare_next_development_iteration release_success_callback]
      downstream.each do |id|
        step = steps.find { |item| item['id'] == id }
        expect(steps.index(step)).to be > steps.index(validation)
        expect(step.fetch('if')).to include("steps.validate_release.outputs.proceed == 'true'")
      end
    end

    it 'rejects missing, invalid, duplicate, and failed command decisions rather than skipping' do
      run_phase('Capture Release Context')
      [
        'true',
        'echo "proceed=maybe" >> "$GITHUB_OUTPUT"',
        'printf "proceed=true\nproceed=false\n" >> "$GITHUB_OUTPUT"',
        'printf "proceed=true\nproceed=\n" >> "$GITHUB_OUTPUT"',
        'echo "proceed=false" >> "$GITHUB_OUTPUT"; exit 1'
      ].each do |command|
        environment['RELEASE_TEST_VALIDATION_COMMAND'] = command
        expect { run_phase('Validate Release') }.to raise_error(RuntimeError)
        expect(validation_decision).to be_nil
        expect(File).not_to exist(environment.fetch('GITHUB_STEP_SUMMARY'))
        expect(Dir[File.join(directory, 'release-validation.*')]).to be_empty
      end
    end

    it 'fails malformed pending sections and delivers the validation exception instead of skipping' do
      File.write(File.join(checkout, 'CHANGELOG.md'), "## [Unreleased]\n\n## [Unreleased]\n")
      run_git('-C', checkout, 'add', 'CHANGELOG.md')
      run_git('-C', checkout, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'commit', '--quiet', '-m', 'Malformed notes')
      run_git('-C', checkout, 'push', '--quiet', 'origin', 'master')
      run_phase('Enable Release Failure Callback')
      run_phase('Capture Release Context')
      expect { run_phase('Validate Release') }.to raise_error(/exactly one matching heading/)
      expect(validation_decision).to be_nil
      environment['RELEASE_STEPS'] = JSON.generate('validate_release' => { 'outcome' => 'failure' })
      run_phase('Determine Release Failure Phase')
      run_phase('Run Release Failure Callback')
      failure = JSON.parse(File.read(File.join(directory, 'failure.json')))
      expect(failure.first(2)).to eq(['0.1.0', 'validate_release'])
      expect(failure.last).to include('exactly one matching heading')
      expect(run_git('-C', checkout, 'status', '--porcelain')).to eq('')
      expect(File).not_to exist(File.join(directory, 'publication.jsonl'))
    end
  end

  shared_examples 'skips empty release notes' do |content|
    before do
      File.write(File.join(checkout, 'CHANGELOG.md'), content)
      run_git('-C', checkout, 'add', 'CHANGELOG.md')
      run_git('-C', checkout, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'commit', '--quiet', '-m', 'Empty release fixture')
      run_git('-C', checkout, 'push', '--quiet', 'origin', 'master')
    end

    it 'skips successfully without changing files or invoking downstream callbacks', :aggregate_failures do
      initial = run_git('-C', checkout, 'rev-parse', 'HEAD')
      environment['INPUT_VERSION'] = '2.0.0'
      run_phase('Configure Release Inputs') if steps.any? { |item| item['name'] == 'Configure Release Inputs' }
      run_phase('Capture Release Context')
      run_phase('Validate Release')
      expect(validation_decision).to eq('false')
      expect(File.read(environment.fetch('GITHUB_STEP_SUMMARY'))).to include('Release skipped')
      ['Prepare Release', 'Resolve Prepared Version', 'Test Release', 'Publish Release',
       'Prepare Next Development Iteration', 'Run Release Success Callback'].each do |name|
        run_phase(name)
      end
      expect(File.read(File.join(checkout, 'CHANGELOG.md'))).to eq(content)
      expect(File.read(File.join(checkout, 'lib/example/version.rb'))).to include("VERSION = '0.1.0'")
      expect(run_git('-C', checkout, 'status', '--porcelain')).to eq('')
      expect(run_git('-C', checkout, 'rev-parse', 'HEAD')).to eq(initial)
      expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(initial)
      expect(run_git('-C', checkout, 'tag')).to eq('')
      expect(File).not_to exist(File.join(directory, 'release.gem'))
      expect(File).not_to exist(File.join(directory, 'publication.jsonl'))
      expect(File).not_to exist(File.join(directory, 'success.json'))
      expect(File).not_to exist(File.join(directory, 'failure.json'))
      expect(File).not_to exist(File.join(directory, 'version-lookups.jsonl'))
      expect(Dir[File.join(directory, 'release-validation.*')]).to be_empty
    end
  end

  shared_examples 'a selected release version' do
    it 'releases the selected version and increments from it while retaining the checked-in version', :aggregate_failures do
      environment['INPUT_VERSION'] = '2.0.0'
      run_phase('Configure Release Inputs') if steps.any? { |item| item['name'] == 'Configure Release Inputs' }
      run_phase('Capture Release Context')
      run_phase('Validate Release')
      run_phase('Prepare Release')
      expect(File.read(File.join(checkout, 'lib/example/version.rb'))).to include("VERSION = '2.0.0'")
      expect(run_git('-C', checkout, 'diff', '--cached', '--name-only').lines.map(&:strip)).to contain_exactly('CHANGELOG.md', 'lib/example/version.rb')
      run_phase('Resolve Prepared Version')
      expect(environment.values_at('RELEASE_VERSION', 'RELEASE_PREVIOUS_VERSION')).to eq(%w[2.0.0 0.1.0])
      run_phase('Publish Release')
      release_commit = run_git('-C', checkout, 'rev-parse', 'v2.0.0')
      expect(Gem::Package.new(File.join(directory, 'release.gem')).spec.version.to_s).to eq('2.0.0')
      expect(run_git('--git-dir', remote, 'rev-parse', 'v2.0.0')).to eq(release_commit)
      expect(File.read(File.join(checkout, 'CHANGELOG.md'))).to include('2.0.0')
      run_phase('Prepare Next Development Iteration')
      expect(File.read(File.join(checkout, 'lib/example/version.rb'))).to include("VERSION = '2.0.1'")
      expect(run_git('-C', checkout, 'log', '-1', '--format=%s')).to eq('Prepare next development iteration, 2.0.1')
      expect(run_git('-C', checkout, 'status', '--porcelain')).to eq('')
      expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(run_git('-C', checkout, 'rev-parse', 'HEAD'))
      expect(environment.fetch('RELEASE_PREVIOUS_VERSION')).to eq('0.1.0')
    end

    it 'rejects invalid selections before changing the version or changelog', :aggregate_failures do
      environment['INPUT_VERSION'] = '02.0.0'
      expect { run_phase('Capture Release Context') }.to raise_error(/MAJOR.MINOR.PATCH/)
      expect(File.read(File.join(checkout, 'lib/example/version.rb'))).to include("VERSION = '0.1.0'")
      expect(File.read(File.join(checkout, 'CHANGELOG.md'))).to eq(consumer_changelog)
      expect(run_git('-C', checkout, 'status', '--porcelain')).to eq('')
      expect(run_git('--git-dir', remote, 'tag')).to eq('')
    end
  end

  shared_examples 'invokes failure callbacks after a failed phase' do
    it 'passes available release context and the failed phase to the failure callback', :aggregate_failures do
      run_phase('Configure Release Inputs') if steps.any? { |item| item['name'] == 'Configure Release Inputs' }
      run_phase('Enable Release Failure Callback')
      run_phase('Capture Release Context')
      run_phase('Validate Release')
      run_phase('Prepare Release')
      environment['RELEASE_TEST_VERSION_STATUS'] = '200'
      expect { run_phase('Resolve Prepared Version') }.to raise_error(/already published/)
      environment['RELEASE_STEPS'] = JSON.generate('resolve_prepared_version' => { 'outcome' => 'failure' })
      run_phase('Determine Release Failure Phase')
      run_phase('Run Release Failure Callback')
      failure = JSON.parse(File.read(File.join(directory, 'failure.json')))
      expect(failure.first(2)).to eq(['0.1.0', 'resolve_prepared_version'])
      expect(failure.last).to include('already published')
      expect(File).not_to exist(File.join(directory, 'publication.jsonl'))
    end
  end

  it_behaves_like 'a local release lifecycle'
  it_behaves_like 'release validation control'
  it_behaves_like 'invokes failure callbacks after a failed phase'
  it_behaves_like 'clean release preparation'
  it_behaves_like 'a selected release version'
  it_behaves_like 'skips empty release notes', "## [Unreleased]\n\n### Fixed\n\n<!-- pending -->\n\n## [0.0.1] - 2026-11-07\n\n- Older notes.\n"

  context 'with Eastern Time' do
    let(:environment) { super().merge('TZ' => 'America/New_York') }

    it_behaves_like 'a local release lifecycle'
  end

  context 'with third-level Intridea release headings' do
    def consumer_rakefile
      super.sub('Changelog::KeepAChangelog.new', "Changelog::Intridea.new(placeholder: '* Your contribution here.')")
    end

    def consumer_changelog
      "### 0.1.0 (Next)\n\n* Change.\n* Your contribution here.\n"
    end

    it_behaves_like 'a local release lifecycle', '### 0.1.1 (Next)'
    it_behaves_like 'a selected release version'
    it_behaves_like 'skips empty release notes', "### 0.1.0 (Next)\n\n* Your contribution here.\n\n### 0.0.1 (2026/11/07)\n\n* Older notes.\n"
  end

  context 'with detailed manual callbacks' do
    def consumer_rakefile
      File.read('docs/usage.md').split('## Custom Callbacks').last[/```ruby\n(.*?)```/m, 1]
          .sub(
            "  tasks.success { |release| puts \"Published \#{release.version}\" }",
            "  tasks.success(&#{result_callback('success')})"
          )
          .sub(/  tasks.failure do \|failure\|\n.*?\n  end/m, "  tasks.failure(&#{result_callback('failure')})")
    end

    it_behaves_like 'a local release lifecycle'
    it_behaves_like 'a selected release version'
  end

  context 'when package publication fails' do
    def publication_stub
      super.sub('status.define_singleton_method(:success?) { true }', 'status.define_singleton_method(:success?) { false }')
    end

    it 'retains recovery artifacts without pushing the release', :aggregate_failures do
      initial = run_git('--git-dir', remote, 'rev-parse', 'master')
      run_phase('Enable Release Failure Callback')
      run_phase('Capture Release Context')
      run_phase('Validate Release')
      run_phase('Prepare Release')
      run_phase('Resolve Prepared Version')
      expect { run_phase('Publish Release') }.to raise_error(/Package command failed/)
      expect(File).to exist(File.join(directory, 'release.gem'))
      expect(File).to exist(File.join(directory, 'release.json'))
      expect(File).to exist(File.join(directory, 'release.bundle'))
      expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(initial)
      expect(run_git('--git-dir', remote, 'tag')).to eq('')
      expect(File.readlines(File.join(directory, 'publication.jsonl')).length).to eq(1)
      environment['RELEASE_STEPS'] = JSON.generate('publish_release' => { 'outcome' => 'failure' })
      run_phase('Determine Release Failure Phase')
      run_phase('Run Release Failure Callback')
      failure = JSON.parse(File.read(File.join(directory, 'failure.json')))
      expect(failure.first(2)).to eq(['0.1.0', 'publish_release'])
      expect(failure.last).to include('Package command failed')
    end
  end

  context 'with the composite action' do
    let(:workflow) { YAML.load_file('action.yml') }

    def steps
      workflow.fetch('runs').fetch('steps')
    end

    def inputs
      workflow.fetch('inputs')
    end

    it_behaves_like 'a local release lifecycle'
    it_behaves_like 'release validation control'
    it_behaves_like 'invokes failure callbacks after a failed phase'
    it_behaves_like 'clean release preparation'
    it_behaves_like 'a selected release version'
    it_behaves_like 'skips empty release notes', "## [Unreleased]\n\n### Fixed\n\n<!-- pending -->\n\n## [0.0.1] - 2026-11-07\n\n- Older notes.\n"

    context 'with Intridea changelogs' do
      def consumer_rakefile
        super.sub('Changelog::KeepAChangelog.new', "Changelog::Intridea.new(placeholder: '* Your contribution here.')")
      end

      it_behaves_like 'skips empty release notes', "### 0.1.0 (Next)\n\n* Your contribution here.\n\n### 0.0.1 (2026/11/07)\n\n* Older notes.\n"
    end

    context 'with Eastern Time' do
      let(:environment) { super().merge('TZ' => 'America/New_York') }

      it_behaves_like 'a local release lifecycle'
    end

    it 'selects owner-aware authentication and preserves artifacts after failures', :aggregate_failures do
      expect(steps.find { |item| item['name'] == 'Configure Release Inputs' }.dig('env', 'TZ')).to eq('${{ inputs.timezone }}')
      expect(steps.find { |item| item['name'] == 'Authenticate to RubyGems' }.fetch('if')).to eq("${{ steps.validate_release.outputs.proceed == 'true' && inputs.rubygems-owner == '' }}")
      expect(steps.find { |item| item['name'] == 'Authenticate Pending Publisher' }.fetch('if')).to eq("${{ steps.validate_release.outputs.proceed == 'true' && inputs.rubygems-owner != '' }}")
      expect(steps.find { |item| item['name'] == 'Preserve Release Artifacts' }.fetch('if')).to include('always()')
    end
  end

  it 'invokes publication and preserves artifacts after a failed callback', :aggregate_failures do
    steps = workflow.fetch('jobs').fetch('release').fetch('steps')
    expect(workflow.dig('jobs', 'release', 'env', 'TZ')).to eq('${{ inputs.timezone }}')
    publish = steps.find { |item| item['name'] == 'Publish Release' }
    artifacts = steps.find { |item| item['name'] == 'Preserve Release Artifacts' }
    expect(publish.fetch('if')).to include("steps.validate_release.outputs.proceed == 'true'")
    expect(artifacts.fetch('if')).to include('always()')
    expect(steps.index(artifacts)).to be > steps.index(publish)
    expect(steps.find { |item| item['name'] == 'Authenticate to RubyGems' }.fetch('if')).to eq("${{ steps.validate_release.outputs.proceed == 'true' && inputs.rubygems-owner == '' }}")
    expect(steps.find { |item| item['name'] == 'Authenticate Pending Publisher' }.fetch('if')).to eq("${{ steps.validate_release.outputs.proceed == 'true' && inputs.rubygems-owner != '' }}")
    enable_failure = steps.find { |item| item['name'] == 'Enable Release Failure Callback' }
    failure_phase = steps.find { |item| item['name'] == 'Determine Release Failure Phase' }
    failure = steps.find { |item| item['name'] == 'Run Release Failure Callback' }
    success = steps.find { |item| item['name'] == 'Run Release Success Callback' }
    expect(steps.index(enable_failure)).to be < steps.index(steps.find { |item| item['name'] == 'Capture Release Context' })
    expect(failure_phase.dig('env', 'RELEASE_STEPS')).to eq('${{ toJSON(steps) }}')
    expect(failure_phase.fetch('run')).to eq('bundle exec rake release:workflow:failure_phase')
    expect(steps.index(failure_phase)).to be < steps.index(failure)
    expect(failure.fetch('if')).to include("failure() && steps.enable_failure_callback.outcome == 'success'")
    expect(failure.dig('env', 'RELEASE_FAILURE_PHASE')).to be_nil
    expect(success.fetch('if')).to eq("${{ success() && steps.validate_release.outputs.proceed == 'true' }}")
    expect(steps.index(success)).to be > steps.index(steps.find { |item| item['name'] == 'Prepare Next Development Iteration' })
  end
end
