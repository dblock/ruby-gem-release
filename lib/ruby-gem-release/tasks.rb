# frozen_string_literal: true

require 'rake'
require_relative 'release'
require_relative 'release_failure'
require_relative 'execution_provider'
require_relative 'version/ruby_constant'
require_relative 'workflow/environment'
require_relative 'workflow/failure'
require_relative 'workflow/ruby_gems_credentials'
require_relative 'destination/ruby_gems'

module RubyGemRelease
  class Tasks
    include Rake::DSL

    def self.install(workflow: nil, package: nil, destination: Destination::RubyGems.new, provider: ExecutionProvider.current)
      instance = new(workflow: workflow, package: package, destination: destination, provider: provider)
      yield instance if block_given?
      instance.install
    end

    def initialize(workflow: nil, package: nil, destination: Destination::RubyGems.new, provider: ExecutionProvider.current)
      @workflow = workflow
      @package = package
      @destination = destination
      @provider = provider
    end

    def install
      namespace :release do
        install_validate_task
        install_callback_tasks
        install_publish_task
        install_result_tasks
        install_workflow_tasks
      end
    end

    def validate(&block)
      raise ArgumentError, 'validate requires a block' unless block
      raise ArgumentError, 'validate already configured' if @validate

      @validate = block
    end

    def prepare(&block)
      raise ArgumentError, 'prepare requires a block' unless block
      raise ArgumentError, 'prepare already configured' if @prepare

      @prepare = block
    end

    def bump(&block)
      raise ArgumentError, 'bump requires a block' unless block
      raise ArgumentError, 'bump already configured' if @bump

      @bump = block
    end

    def publish(&block)
      raise ArgumentError, 'publish requires a block' unless block
      raise ArgumentError, 'publish already configured' if @publish

      @publish = block
    end

    def success(&block)
      raise ArgumentError, 'success requires a block' unless block
      raise ArgumentError, 'success already configured' if @success

      @success = block
    end

    def failure(&block)
      raise ArgumentError, 'failure requires a block' unless block
      raise ArgumentError, 'failure already configured' if @failure

      @failure = block
    end

    private

    def install_validate_task
      desc 'Validate release preconditions'
      task :validate do
        with_failure_capture('release:validate') { validate_release }
      end
    end

    def validate_release
      raise ArgumentError, 'Release validation failed: callback returned false' if @validate && @validate.call(context('release:validate', preparing: true)) == false

      puts 'Release validation passed.'
    end

    def install_workflow_tasks
      namespace :workflow do
        install_workflow_context_tasks
        task(:failure_phase) { Workflow::Failure.phase!(provider: @provider) }
        task(:credentials) do
          with_failure_capture('release:workflow:credentials') do
            Workflow::RubyGemsCredentials.new(owner: @provider.fetch('RUBYGEMS_OWNER_ID', ''), provider: @provider).configure!
          end
        end
      end
    end

    def install_workflow_context_tasks
      install_checkpoint_task
      task(:configure) { with_failure_capture('release:workflow:configure') { Workflow::Environment.new(provider: @provider).configure! } }
      task(:capture) { with_failure_capture('release:workflow:capture') { Workflow::Environment.new(provider: @provider).capture!(package: @package) } }
      task(:resolve) do
        with_failure_capture('release:workflow:resolve') do
          Workflow::Environment.new(provider: @provider).resolve!(package: @package, destination: @destination, analysis: state.analysis)
        end
      end
    end

    def install_checkpoint_task
      task(:checkpoint) do
        with_failure_capture('release:workflow:checkpoint') do
          raise 'Workflow must implement checkpoint! before publication' unless @workflow

          @workflow.checkpoint!(context('release:workflow:checkpoint'))
        end
      end
    end

    def install_publish_task
      desc 'Run the release publication callback'
      task :publish do
        with_failure_capture('release:publish') do
          next unless @publish

          ctx = context('release:publish')
          @destination.authenticate!(provider: @provider) unless @workflow&.published?(ctx.release)
          @publish.call(ctx)
        end
      end
    end

    def install_result_tasks
      desc 'Run the release success callback'
      task :success do
        with_failure_capture('release:success') { @success&.call(context('release:success')) }
      end
      desc 'Run the release failure callback'
      task :failure do
        @failure&.call(failure_context)
      end
    end

    def install_callback_tasks
      install_prepare_task
      install_bump_task
    end

    def install_prepare_task
      desc 'Run the release preparation callback'
      task(:prepare) do
        with_failure_capture('release:prepare') do
          execution = context('release:prepare', preparing: true)
          @prepare&.call(execution)
        end
      end
    end

    def install_bump_task
      desc 'Run the next development iteration preparation callback'
      task(:bump) do
        with_failure_capture('release:bump') do
          execution = context('release:bump')
          @bump&.call(execution)
        end
      end
    end

    def context(task, preparing: false)
      snapshot = state.snapshot
      release = release_context(preparing: preparing, **snapshot, validating: task == 'release:validate')
      @provider.context(release: release, task: task, state: state, workflow: @workflow, analysis: snapshot.fetch(:analysis))
    end

    def state
      path = @provider.fetch('RELEASE_STATE_FILE', nil)
      if !defined?(@state) || @state_path != path
        @state_path = path
        @state = Workflow::State.new(path: path)
      end
      @state
    end

    def release_context(preparing: false, analysis: nil, next_version: nil, validating: false)
      gemspec_version = @provider.fetch('GEMSPEC_VERSION')
      version = preparing ? preparation_version(gemspec_version, analysis: analysis, validating: validating) : @provider.fetch('RELEASE_VERSION')
      date = @provider.fetch('RELEASE_DATE')
      analysis&.check!(head: @provider.fetch('SOURCE_COMMIT'), explicit_version: @provider.fetch('INPUT_VERSION', ''), version: validating ? nil : version)
      validate_context_versions(version, gemspec_version)
      raise ArgumentError, 'release date is required in YYYY-MM-DD format' unless date.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Release.new(version: version, gemspec_version: gemspec_version, date: Date.iso8601(date), next_version: next_version, notes: analysis&.notes)
    end

    def preparation_version(gemspec_version, analysis: nil, validating: false)
      if analysis
        return analysis.version if analysis.release?
        return gemspec_version if validating

        raise ArgumentError, 'semantic analysis selected no release'
      end
      selected = @provider.fetch('INPUT_VERSION', '')
      selected.empty? ? gemspec_version : selected
    end

    def failure_context
      phase = @provider.fetch('RELEASE_FAILED_STEP_ID', 'unknown')
      error = Workflow::Failure.error_for(phase, provider: @provider) unless phase == 'unknown'
      safe_state, snapshot = failure_snapshot
      execution = @provider.context(release: failure_release_context(**snapshot), task: 'release:failure', state: safe_state, workflow: @workflow, analysis: snapshot.fetch(:analysis))
      ReleaseFailure.new(phase: phase, error: error, context: execution)
    end

    def failure_release_context(analysis: nil, next_version: nil)
      gemspec_version = @provider.fetch('GEMSPEC_VERSION', nil)
      date = @provider.fetch('RELEASE_DATE', '')
      return unless gemspec_version && date.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      version = @provider.fetch('RELEASE_VERSION', '')
      version = preparation_version(gemspec_version, analysis: analysis) if version.empty?
      validate_context_versions(version, gemspec_version)
      Release.new(version: version, gemspec_version: gemspec_version, date: Date.iso8601(date), next_version: next_version, notes: analysis&.notes)
    rescue ArgumentError
      nil
    end

    def failure_snapshot
      [state, state.snapshot]
    rescue ArgumentError, JSON::ParserError, SystemCallError => e
      warn "Unable to read release state for failure callback: #{e.message}"
      safe_state = Workflow::State.new
      [safe_state, safe_state.snapshot]
    end

    def with_failure_capture(task)
      yield
    rescue StandardError => e
      Workflow::Failure.capture!(@provider.step_id(task), e, provider: @provider)
      raise
    end

    def validate_context_versions(*versions)
      pattern = Version::RubyConstant::PATTERN
      versions.compact.each do |value|
        raise ArgumentError, "invalid version: #{value.inspect}; expected MAJOR.MINOR.PATCH" unless value.is_a?(String) && pattern.match?(value)
      end
    end
  end
end
