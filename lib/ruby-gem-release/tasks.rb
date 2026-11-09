# frozen_string_literal: true

require 'rake'
require_relative 'release'
require_relative 'release_failure'
require_relative 'version/ruby_constant'
require_relative 'workflow/context'
require_relative 'workflow/failure'
require_relative 'workflow/ruby_gems_credentials'

module RubyGemRelease
  class Tasks
    include Rake::DSL

    def self.install
      instance = new
      yield instance if block_given?
      instance.install
    end

    def install
      namespace :release do
        install_callback_tasks
        install_publish_task
        install_result_tasks
        install_workflow_tasks
      end
    end

    def before_release(&block)
      raise ArgumentError, 'before_release requires a block' unless block
      raise ArgumentError, 'before_release already configured' if @before_release

      @before_release = block
    end

    def after_release(&block)
      raise ArgumentError, 'after_release requires a block' unless block
      raise ArgumentError, 'after_release already configured' if @after_release

      @after_release = block
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

    def install_workflow_tasks
      namespace :workflow do
        install_workflow_context_tasks
        task(:failure_phase) { Workflow::Failure.phase! }
        task(:credentials) do
          with_failure_capture('authenticate_pending_publisher') do
            Workflow::RubyGemsCredentials.new(owner: ENV.fetch('RUBYGEMS_OWNER')).configure!
          end
        end
      end
    end

    def install_workflow_context_tasks
      task(:configure) { with_failure_capture('configure_release_inputs') { Workflow::Context.new.configure! } }
      task(:capture) { with_failure_capture('capture_release_context') { Workflow::Context.new.capture! } }
      task(:resolve) { with_failure_capture('resolve_prepared_version') { Workflow::Context.new.resolve! } }
    end

    def install_publish_task
      desc 'Run the release publication callback'
      task :publish do
        with_failure_capture('publish_release') { @publish&.call(context) }
      end
    end

    def install_result_tasks
      desc 'Run the release success callback'
      task :success do
        with_failure_capture('release_success_callback') { @success&.call(context) }
      end
      desc 'Run the release failure callback'
      task :failure do
        @failure&.call(failure_context)
      end
    end

    def install_callback_tasks
      install_before_release_task
      install_after_release_task
    end

    def install_before_release_task
      desc 'Run the before-release callback'
      task(:before_release) do
        with_failure_capture('prepare_release') do
          release = context(before_release: true)
          @before_release&.call(release)
        end
      end
    end

    def install_after_release_task
      desc 'Run the next development iteration preparation callback'
      task(:after_release) do
        with_failure_capture('prepare_next_development_iteration') do
          release = context
          @after_release&.call(release)
        end
      end
    end

    def context(before_release: false)
      previous_version = ENV.fetch('RELEASE_PREVIOUS_VERSION')
      version = before_release ? preparation_version(previous_version) : ENV.fetch('RELEASE_VERSION')
      date = ENV.fetch('RELEASE_DATE')
      validate_context_versions(version, previous_version)
      raise ArgumentError, 'release date is required in YYYY-MM-DD format' unless date.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Release.new(version: version, previous_version: previous_version, date: Date.iso8601(date))
    end

    def preparation_version(previous_version)
      selected = ENV.fetch('INPUT_VERSION', '')
      selected.empty? ? previous_version : selected
    end

    def failure_context
      phase = ENV.fetch('RELEASE_FAILURE_PHASE', 'unknown')
      error = Workflow::Failure.error_for(phase) unless phase == 'unknown'
      ReleaseFailure.new(phase: phase, error: error, release: failure_release_context)
    end

    def failure_release_context
      previous_version = ENV.fetch('RELEASE_PREVIOUS_VERSION', nil)
      date = ENV.fetch('RELEASE_DATE', '')
      return unless previous_version && date.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      version = ENV['RELEASE_VERSION'] || preparation_version(previous_version)
      validate_context_versions(version, previous_version)
      Release.new(version: version, previous_version: previous_version, date: Date.iso8601(date))
    rescue ArgumentError
      nil
    end

    def with_failure_capture(phase)
      yield
    rescue StandardError => e
      Workflow::Failure.capture!(phase, e)
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
