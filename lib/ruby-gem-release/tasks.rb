# frozen_string_literal: true

require 'rake'
require_relative 'release'
require_relative 'version/ruby_constant'

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

    private

    def install_callback_tasks
      desc 'Run the before-release callback'
      task(:before_release, %i[version previous_version date]) do |_task, args|
        release = context(args)
        @before_release&.call(release)
      end
      desc 'Run the next-version preparation callback'
      task(:after_release, %i[version previous_version date]) do |_task, args|
        release = context(args)
        @after_release&.call(release)
      end
    end

    def context(args)
      version = args[:version]
      validate_context_versions(version, args[:previous_version])
      raise ArgumentError, 'release date is required in YYYY-MM-DD format' unless args[:date]&.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      raise ArgumentError, 'release version and previous version are required' unless version && args[:previous_version]

      Release.new(version: version, previous_version: args[:previous_version], date: Date.iso8601(args[:date]))
    end

    def validate_context_versions(*versions)
      pattern = Version::RubyConstant::PATTERN
      versions.compact.each do |value|
        raise ArgumentError, "invalid version: #{value.inspect}; expected MAJOR.MINOR.PATCH" unless value.is_a?(String) && pattern.match?(value)
      end
    end
  end
end
