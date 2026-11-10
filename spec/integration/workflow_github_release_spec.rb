# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require 'open3'
require 'tmpdir'
require 'rubygems/package'

RSpec.describe 'Workflow release lifecycle' do
  let(:directory) { Dir.mktmpdir }
  let(:runner) { { checkout: 'checkout', initial_environment: environment.dup } }
  let(:remote) { File.join(directory, 'remote.git') }
  let(:workflow) { YAML.load_file('.github/workflows/release.yml') }
  let(:environment) do
    ENV.to_h.slice('PATH', 'HOME', 'TMPDIR', 'LANG').merge(
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
      'GITHUB_ACTIONS' => 'true',
      'GITHUB_WORKFLOW_REF' => 'owner/example/.github/workflows/publish.yml@refs/heads/master',
      'GITHUB_RUN_ID' => '123',
      'GITHUB_RUN_ATTEMPT' => '2',
      'DEFAULT_BRANCH' => 'master',
      'GITHUB_REF' => 'refs/heads/master',
      'INPUT_VERSION' => '',
      'INPUT_GEMSPEC' => '',
      'SOURCE_DATE_EPOCH' => '',
      'GIT_USER_NAME' => 'Fixture',
      'GIT_USER_EMAIL' => 'fixture@example.com',
      'RUBYGEMS_OWNER' => '',
      'ACTIONS_ID_TOKEN_REQUEST_URL' => 'https://oidc.example.test/token',
      'ACTIONS_ID_TOKEN_REQUEST_TOKEN' => 'fixture-request-token',
      'TZ' => inputs.fetch('timezone').fetch('default'),
      'RELEASE_TEST_REMOTE' => remote,
      'RELEASE_TEST_SERVICE_DIRECTORY' => directory
    )
  end

  def checkout
    File.join(directory, runner.fetch(:checkout))
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
      "->(ctx) { #{context_record('ctx')}; File.write(File.join(ENV.fetch('RUNNER_TEMP'), 'success.json'), " \
        'JSON.generate([ctx.release.version, ctx.release.previous_version, ctx.release.next_version])) }'
    else
      "->(failure) { #{context_record('failure.context')}; File.write(File.join(ENV.fetch('RUNNER_TEMP'), 'failure.json'), " \
        'JSON.generate([failure.context.release&.version, failure.phase, failure.error&.message])) }'
    end
  end

  def context_record(expression)
    "File.write(File.join(ENV.fetch('RUNNER_TEMP'), 'context.json'), JSON.generate({" \
      "step: #{expression}.step.id, steps: #{expression}.steps.transform_values { |s| [s.outcome, s.conclusion, s.outputs] }, " \
      "repository: #{expression}.run.repository, run_id: #{expression}.run.run_id, attempt: #{expression}.run.run_attempt, " \
      "workflow: #{expression}.workflow&.class&.name, context_class: #{expression}.class.name}))"
  end

  # Self-release runs this suite after the real workflow has exported its context.
  around do |example|
    original = ENV.to_h
    ENV.update(
      'GEMSPEC' => File.expand_path('ruby-gem-release.gemspec'),
      'RELEASE_VERSION' => '9.9.9',
      'RELEASE_PREVIOUS_VERSION' => '9.9.8',
      'RELEASE_DATE' => '2020-01-01',
      'RELEASE_DIRECTORY' => File.join(directory, 'outer-release'),
      'RELEASE_STATE' => File.join(directory, 'outer-state.json'),
      'RELEASE_AUTHENTICATION' => 'rubygems'
    )
    example.run
  ensure
    ENV.replace(original)
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
    FileUtils.cp('examples/keep_a_changelog/CHANGELOG.md', File.join(checkout, 'CHANGELOG.md'))
    File.write(File.join(checkout, 'Rakefile'), "#{consumer_rakefile}\n#{publication_stub}\n#{File.read('spec/fixtures/authentication.rb')}")
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
          service = ENV.fetch('RELEASE_TEST_SERVICE_DIRECTORY')
          if command[0, 3] == ['gh', 'api', '--include']
            endpoint = command.last
            raise 'Unexpected artifact discovery' if endpoint.include?('/actions/')
            path = File.join(service, 'hosting.json')
            data = File.file?(path) ? JSON.parse(File.read(path)) : nil
            code = data ? '200 OK' : '404 Not Found'
            return ["HTTP/2.0 " + code + "\\n\\n" + JSON.generate(data), '', Struct.new(:success?).new(true)]
          end
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
          if status.success? && upload
            File.write(File.join(service, 'registry.json'), JSON.generate(sha: Digest::SHA256.file(command.last).hexdigest))
          elsif status.success?
            File.write(File.join(service, 'hosting.json'), JSON.generate(
              tag_name: 'v' + version, name: 'v' + version, draft: false, prerelease: false,
              html_url: 'https://github.com/owner/example/releases/tag/v' + version,
              assets: [{name: File.basename(command.last), digest: 'sha256:' + Digest::SHA256.file(command.last).hexdigest}]
            ))
          end
          status = Struct.new(:success?).new(false) if upload && ENV['RELEASE_TEST_LOST_UPLOAD_RESPONSE'] == 'true'
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
            saved = File.join(ENV.fetch('RELEASE_TEST_SERVICE_DIRECTORY'), 'registry.json')
            published = File.file?(saved)
            Struct.new(:code, :body).new(ENV.fetch('RELEASE_TEST_VERSION_STATUS', published ? '200' : '404'), published ? File.read(saved) : '{}')
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

  def steps
    workflow.fetch('jobs').fetch('release').fetch('steps')
  end

  def inputs
    workflow.fetch(true).fetch('workflow_call').fetch('inputs')
  end

  def phase_command(name)
    step = steps.find { |item| item['name'] == name }
    return step.fetch('run') if name == 'Validate Release'

    command_input = step.dig('env', 'COMMAND')
    command_input ? inputs.fetch(command_input[/inputs\.(\w+)/, 1]).fetch('default') : step.fetch('run')
  end

  def run_phase(name)
    step = steps.find { |item| item['name'] == name }
    return record_outcome(step, 'skipped') if skipped_phase?(step)

    output, error, status = Open3.capture3(phase_environment(name), 'bash', '-euo', 'pipefail', '-c', phase_command(name), chdir: checkout, unsetenv_others: true)
    record_outcome(step, status.success? ? 'success' : 'failure')
    raise "#{output}\n#{error}" unless status.success?

    import_environment
  end

  def fresh_runner(source:)
    runner[:checkout] = 'fresh-checkout'
    checkout_source(source)
    environment.replace(runner.fetch(:initial_environment).merge('RUNNER_TEMP' => File.join(directory, 'fresh-runner'), 'GITHUB_RUN_ID' => '124', 'GITHUB_RUN_ATTEMPT' => '1'))
    reset_workflow_files
    executed_steps.clear
    configure_inputs
  end

  def checkout_source(source)
    run_git('clone', '--quiet', remote, checkout)
    run_git('-C', checkout, 'switch', '--detach', source)
  end

  def configure_inputs
    run_phase('Configure Release Inputs') if steps.any? { |step| step['name'] == 'Configure Release Inputs' }
  end

  def reset_workflow_files
    FileUtils.mkdir_p(environment.fetch('RUNNER_TEMP'))
    %w[GITHUB_ENV GITHUB_OUTPUT GITHUB_STEP_SUMMARY].each do |key|
      environment[key] = File.join(environment.fetch('RUNNER_TEMP'), key)
      File.write(environment[key], '')
    end
  end

  def skipped_phase?(step)
    return false if step.fetch('if', '').include?('failure()')

    executed_steps.values.any? { |value| value['outcome'] == 'failure' }
  end

  def import_environment
    File.readlines(environment.fetch('GITHUB_ENV'), chomp: true).each do |line|
      key, value = line.split('=', 2)
      environment[key] = value
    end
  end

  def record_outcome(step, outcome)
    executed_steps[step.fetch('id')] = { 'outcome' => outcome, 'conclusion' => outcome }
  end

  def phase_environment(name)
    step = steps.find { |item| item['name'] == name }
    values = environment.dup
    values['COMMAND'] = validation_command if name == 'Validate Release'
    values['RELEASE_STEP_ID'] = step.dig('env', 'RELEASE_STEP_ID') if step.dig('env', 'RELEASE_STEP_ID')
    values['RELEASE_STEPS'] = JSON.generate(executed_steps) if step.dig('env', 'RELEASE_STEPS')
    values
  end

  def executed_steps
    @executed_steps ||= {}
  end

  def validation_command
    inputs.fetch('validate').fetch('default')
  end

  shared_examples 'a local release lifecycle' do |owner|
    it 'publishes, transports credentials, and bumps using real separate processes', :aggregate_failures do
      environment['HOME'] = File.join(directory, 'home')
      FileUtils.mkdir_p(environment.fetch('HOME'))
      environment['RUBYGEMS_OWNER'] = owner.to_s
      source_epoch = run_git('-C', checkout, 'show', '-s', '--format=%ct', 'HEAD')
      configure_inputs
      run_phase('Capture Release Context')
      expect(environment.fetch('SOURCE_DATE_EPOCH')).to eq(source_epoch)
      run_phase('Validate Release')
      run_phase('Prepare Release')
      run_phase('Resolve Prepared Version')
      run_phase('Checkpoint Release')
      run_phase('Publish Release')
      exchange = { 'jwt' => 'fixture-oidc-token' }
      exchange['owner'] = owner unless owner.to_s.empty?
      expect(JSON.parse(File.read(File.join(directory, 'authentication.json')))).to eq(exchange)
      command = 'puts JSON.generate(ENV.values_at("RUBYGEMS_API_KEY", "BUNDLE_GEM__PUSH_KEY", "GEM_HOST_API_KEY"))'
      output, error, status = Open3.capture3(environment, Gem.ruby, '-rjson', '-e', command, chdir: checkout, unsetenv_others: true)
      expect(status.success?).to be(true), error
      expect(JSON.parse(output)).to eq(['fixture-api-key'] * 3)
      expect(File).not_to exist(File.join(environment.fetch('HOME'), '.gem', 'credentials'))
      release_commit = run_git('-C', checkout, 'rev-parse', 'HEAD')
      expect(run_git('-C', checkout, 'rev-parse', 'v0.1.0')).to eq(release_commit)
      expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(release_commit)
      expect(run_git('--git-dir', remote, 'rev-parse', 'v0.1.0')).to eq(release_commit)
      expect(Gem::Package.new(File.join(directory, 'release.gem')).spec.version.to_s).to eq('0.1.0')
      expect(Gem::Package.new(File.join(directory, 'release.gem')).spec.date.to_date).to eq(Time.at(source_epoch.to_i).utc.to_date)
      File.open(File.join(directory, 'release.gem'), 'rb') do |file|
        Gem::Package::TarReader.new(file) do |tar|
          expect(tar.first.header.mtime).to eq(source_epoch.to_i)
        end
      end
      expect(File).to exist(File.join(directory, 'release.bundle'))
      run_phase('Prepare Next Development Iteration')
      run_phase('Run Release Success Callback')
      expect(JSON.parse(File.read(File.join(directory, 'success.json')))).to eq(%w[0.1.0 0.1.0 0.1.1])
      execution = JSON.parse(File.read(File.join(directory, 'context.json')))
      expect(execution).to include('step' => 'release_success_callback', 'repository' => 'owner/example', 'run_id' => '123', 'attempt' => '2')
      expect(execution.fetch('context_class')).to eq('RubyGemRelease::ExecutionContext::GitHub')
      expect(execution.fetch('steps').fetch('validate_release')).to eq(['success', 'success', {}])
      expect(execution.fetch('steps').fetch('publish_release').first).to eq('success')
      expect(execution.fetch('steps')).not_to have_key('release_success_callback')
      expect(run_git('-C', checkout, 'log', '-1', '--format=%s')).to eq('Prepare next development iteration, 0.1.1')
      expect(File.read(File.join(checkout, 'lib/example/version.rb'))).to include("VERSION = '0.1.1'")
      expect(File.read(File.join(checkout, 'CHANGELOG.md'))).to include('## [Unreleased]')
      expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(run_git('-C', checkout, 'rev-parse', 'HEAD'))
      expect(run_git('--git-dir', remote, 'rev-parse', 'v0.1.0')).to eq(release_commit)
      expect(run_git('-C', checkout, 'status', '--porcelain')).to eq('')
      artifact = File.join(directory, 'example-0.1.0.gem')
      publications = File.readlines(File.join(directory, 'publication.jsonl')).map { |line| JSON.parse(line) }
      expect(publications).to eq([
                                   [Gem.ruby, '-S', 'gem', 'push', artifact],
                                   ['gh', 'release', 'create', 'v0.1.0', '--repo', 'owner/example', '--verify-tag',
                                    '--title', 'v0.1.0', '--generate-notes', artifact]
                                 ])
    end
  end

  shared_examples 'rejects empty release notes' do
    it 'fails validation and reports it without changing files or invoking downstream release operations', :aggregate_failures do
      content = "## [Unreleased]\n\n### Fixed\n\n<!-- pending -->\n\n## [0.0.1] - 2026-11-07\n\n- Older notes.\n"
      File.write(File.join(checkout, 'CHANGELOG.md'), content)
      run_git('-C', checkout, 'add', 'CHANGELOG.md')
      run_git('-C', checkout, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.com', 'commit', '--quiet', '-m', 'Empty release fixture')
      run_git('-C', checkout, 'push', '--quiet', 'origin', 'master')
      initial = run_git('-C', checkout, 'rev-parse', 'HEAD')
      environment['INPUT_VERSION'] = '2.0.0'
      configure_inputs
      run_phase('Capture Release Context')
      expect { run_phase('Validate Release') }.to raise_error(/Nothing to release/)
      ['Prepare Release', 'Resolve Prepared Version', 'Test Release', 'Publish Release',
       'Prepare Next Development Iteration', 'Run Release Success Callback'].each { |name| run_phase(name) }
      expect(File.read(File.join(checkout, 'CHANGELOG.md'))).to eq(content)
      expect(File.read(File.join(checkout, 'lib/example/version.rb'))).to include("VERSION = '0.1.0'")
      expect(run_git('-C', checkout, 'status', '--porcelain')).to eq('')
      expect(run_git('-C', checkout, 'rev-parse', 'HEAD')).to eq(initial)
      expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(initial)
      expect(run_git('-C', checkout, 'tag')).to eq('')
      %w[release.gem publication.jsonl success.json failure.json version-lookups.jsonl authentication.json].each do |name|
        expect(File).not_to exist(File.join(directory, name))
      end
      run_phase('Determine Release Failure Phase')
      run_phase('Run Release Failure Callback')
      failure = JSON.parse(File.read(File.join(directory, 'failure.json')))
      expect(failure.first(2)).to eq(['2.0.0', 'validate_release'])
      expect(failure.last).to include('Nothing to release')
    end
  end

  shared_examples 'a custom registry destination' do
    def consumer_rakefile
      configuration = super.sub('  changelog:', "  destination: FixtureRegistry.new,\n  hosting: nil,\n  changelog:")
      "#{File.read('spec/fixtures/registry.rb')}\n#{configuration}"
    end

    def publication_stub
      "#{super}\n" + <<~RUBY
        module RejectRubyGemsRequests
          def start(host, *arguments, **options, &block)
            raise 'Custom registry must not contact RubyGems' if host == 'rubygems.org'

            super
          end
        end
        Net::HTTP.singleton_class.prepend(RejectRubyGemsRequests)
      RUBY
    end

    it 'authenticates and publishes through the configured registry without RubyGems requests' do
      configure_inputs
      run_phase('Capture Release Context')
      run_phase('Validate Release')
      run_phase('Prepare Release')
      run_phase('Resolve Prepared Version')
      expect(environment.fetch('RELEASE_AUTHENTICATION')).to eq('')
      run_phase('Checkpoint Release')
      run_phase('Publish Release')
      expect(environment.fetch('FIXTURE_REGISTRY_TOKEN')).to eq('fixture-registry-token')
      path = JSON.parse(File.read(File.join(directory, 'registry-publish.json')))
      expect(File.binread(path)).to eq(File.binread(File.join(directory, 'release.gem')))
      expect(run_git('--git-dir', remote, 'rev-parse', 'v0.1.0')).to eq(run_git('-C', checkout, 'rev-parse', 'HEAD'))
      checks = File.readlines(File.join(directory, 'registry-checks.jsonl')).map { |line| JSON.parse(line) }
      expect(checks).to eq([%w[example 0.1.0]] * 2)
      expect(File).not_to exist(File.join(directory, 'version-lookups.jsonl'))
      expect(File).not_to exist(File.join(directory, 'publication.jsonl'))
      run_phase('Prepare Next Development Iteration')
      run_phase('Run Release Success Callback')
      expect(JSON.parse(File.read(File.join(directory, 'success.json')))).to eq(%w[0.1.0 0.1.0 0.1.1])
    end
  end

  shared_examples 'a failed publication' do
    def publication_stub
      super.sub('status.define_singleton_method(:success?) { true }', 'status.define_singleton_method(:success?) { false }')
    end

    it 'retains recovery artifacts and reports the error in a later process without pushing', :aggregate_failures do
      initial = run_git('--git-dir', remote, 'rev-parse', 'master')
      run_phase('Capture Release Context')
      run_phase('Validate Release')
      run_phase('Prepare Release')
      run_phase('Resolve Prepared Version')
      run_phase('Checkpoint Release')
      expect { run_phase('Publish Release') }.to raise_error(/Destination command failed/)
      %w[release.gem release.json release.bundle].each { |name| expect(File).to exist(File.join(directory, name)) }
      expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(initial)
      expect(run_git('--git-dir', remote, 'tag')).to eq('')
      expect(File.readlines(File.join(directory, 'publication.jsonl')).length).to eq(1)
      environment['RELEASE_STEPS'] = JSON.generate('publish_release' => { 'outcome' => 'failure' })
      run_phase('Determine Release Failure Phase')
      run_phase('Run Release Failure Callback')
      failure = JSON.parse(File.read(File.join(directory, 'failure.json')))
      expect(failure.first(2)).to eq(['0.1.0', 'publish_release'])
      expect(failure.last).to include('Destination command failed')
    end
  end

  it_behaves_like 'a local release lifecycle', '123'
  it_behaves_like 'a custom registry destination'
  it_behaves_like 'rejects empty release notes'
  it_behaves_like 'a failed publication'

  shared_examples 'repeating accepted publication' do
    it 'rebuilds on a fresh runner after a lost upload response without uploading or incrementing twice' do
      source = run_git('-C', checkout, 'rev-parse', 'HEAD')
      ['Capture Release Context', 'Validate Release', 'Prepare Release', 'Prepare Release', 'Resolve Prepared Version', 'Checkpoint Release'].each { |phase| run_phase(phase) }
      run_phase('Checkpoint Release')
      environment['RELEASE_TEST_LOST_UPLOAD_RESPONSE'] = 'true'
      run_phase('Publish Release')
      expect(run_git('--git-dir', remote, 'tag')).to eq('v0.1.0')
      digest = Digest::SHA256.file(File.join(directory, 'release.gem')).hexdigest
      environment.delete('RELEASE_TEST_LOST_UPLOAD_RESPONSE')
      fresh_runner(source: source)
      run_phase('Capture Release Context')
      ['Validate Release', 'Prepare Release', 'Resolve Prepared Version', 'Checkpoint Release', 'Publish Release', 'Prepare Next Development Iteration'].each { |phase| run_phase(phase) }
      head = run_git('--git-dir', remote, 'rev-parse', 'master')
      run_phase('Prepare Next Development Iteration')
      expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(head)
      original = environment.fetch('RELEASE_INITIAL_COMMIT')
      run_git('-C', checkout, 'switch', '--detach', original)
      run_phase('Configure Release Inputs') if steps.any? { |step| step['name'] == 'Configure Release Inputs' }
      ['Capture Release Context', 'Validate Release', 'Prepare Release', 'Resolve Prepared Version', 'Checkpoint Release', 'Publish Release', 'Prepare Next Development Iteration'].each { |phase| run_phase(phase) }
      expect(run_git('--git-dir', remote, 'rev-parse', 'master')).to eq(head)
      expect(Digest::SHA256.file(File.join(environment.fetch('RUNNER_TEMP'), 'release.gem')).hexdigest).to eq(digest)
      publications = [directory, environment.fetch('RUNNER_TEMP')].flat_map do |path|
        file = File.join(path, 'publication.jsonl')
        File.file?(file) ? File.readlines(file).map { |line| JSON.parse(line) } : []
      end
      expect(publications.count { |command| command.first == Gem.ruby }).to eq(1)
      expect(run_git('--git-dir', remote, 'show', 'master:lib/example/version.rb')).to include("VERSION = '0.1.1'")
      expect(run_git('--git-dir', remote, 'rev-list', '--count', 'master')).to eq('3')
    end
  end

  it_behaves_like 'repeating accepted publication'

  context 'with the composite action' do
    let(:workflow) { YAML.load_file('action.yml') }

    def steps
      workflow.fetch('runs').fetch('steps')
    end

    def inputs
      workflow.fetch('inputs')
    end

    it_behaves_like 'a local release lifecycle', nil
    it_behaves_like 'a custom registry destination'
    it_behaves_like 'rejects empty release notes'
    it_behaves_like 'a failed publication'
    it_behaves_like 'repeating accepted publication'
  end
end
