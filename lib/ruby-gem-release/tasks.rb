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
      desc 'Decide whether to proceed with the release'
      task :validate do
        with_failure_capture('release:validate') { validate_release }
      end
    end

    def validate_release
      proceed = @validate ? @validate.call(context('release:validate', preparing: true)) : true
      raise ArgumentError, 'validate must return true or false' unless [true, false].include?(proceed)

      puts(proceed ? 'Release validation passed.' : 'Release skipped: nothing to release.')
      @provider.output('proceed' => proceed.to_s)
    end

    def install_workflow_tasks
      namespace :workflow do
        install_workflow_context_tasks
        task(:failure_phase) { Workflow::Failure.phase!(provider: @provider) }
        task(:credentials) do
          with_failure_capture('release:workflow:credentials') do
            Workflow::RubyGemsCredentials.new(owner: @provider.fetch('RUBYGEMS_OWNER'), provider: @provider).configure!
          end
        end
      end
    end

    def install_workflow_context_tasks
      task(:configure) { with_failure_capture('release:workflow:configure') { Workflow::Environment.new(provider: @provider).configure! } }
      task(:capture) { with_failure_capture('release:workflow:capture') { Workflow::Environment.new(provider: @provider).capture! } }
      task(:resolve) do
        with_failure_capture('release:workflow:resolve') do
          Workflow::Environment.new(provider: @provider).resolve!(package: @package, destination: @destination)
        end
      end
    end

    def install_publish_task
      desc 'Run the release publication callback'
      task :publish do
        with_failure_capture('release:publish') { @publish&.call(context('release:publish')) }
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
      @provider.context(release: release_context(preparing: preparing), task: task, state: state, workflow: @workflow)
    end

    def state
      path = @provider.fetch('RELEASE_STATE', nil)
      if !defined?(@state) || @state_path != path
        @state_path = path
        @state = Workflow::State.new(path: path)
      end
      @state
    end

    def release_context(preparing: false)
      previous_version = @provider.fetch('RELEASE_PREVIOUS_VERSION')
      version = preparing ? preparation_version(previous_version) : @provider.fetch('RELEASE_VERSION')
      date = @provider.fetch('RELEASE_DATE')
      validate_context_versions(version, previous_version)
      raise ArgumentError, 'release date is required in YYYY-MM-DD format' unless date.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Release.new(version: version, previous_version: previous_version, date: Date.iso8601(date), next_version: state.next_version)
    end

    def preparation_version(previous_version)
      selected = @provider.fetch('INPUT_VERSION', '')
      selected.empty? ? previous_version : selected
    end

    def failure_context
      phase = @provider.fetch('RELEASE_FAILURE_PHASE', 'unknown')
      error = Workflow::Failure.error_for(phase, provider: @provider) unless phase == 'unknown'
      execution = @provider.context(release: failure_release_context, task: 'release:failure', state: state, workflow: @workflow)
      ReleaseFailure.new(phase: phase, error: error, context: execution)
    end

    def failure_release_context
      previous_version = @provider.fetch('RELEASE_PREVIOUS_VERSION', nil)
      date = @provider.fetch('RELEASE_DATE', '')
      return unless previous_version && date.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      version = @provider.fetch('RELEASE_VERSION', '')
      version = preparation_version(previous_version) if version.empty?
      validate_context_versions(version, previous_version)
      Release.new(version: version, previous_version: previous_version, date: Date.iso8601(date), next_version: failure_next_version)
    rescue ArgumentError
      nil
    end

    def failure_next_version
      state.next_version
    rescue ArgumentError, JSON::ParserError, SystemCallError => e
      warn "Unable to read release state for failure callback: #{e.message}"
      nil
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
