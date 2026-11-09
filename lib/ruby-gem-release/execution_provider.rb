# frozen_string_literal: true

require_relative 'execution_context'

module RubyGemRelease
  class ExecutionProvider
    attr_reader :outputs

    def self.current(environment: ENV)
      return new(environment: environment) unless environment['GITHUB_ACTIONS'] == 'true'

      require_relative 'execution_provider/github'
      GitHub.new(environment: environment)
    end

    def initialize(environment: ENV)
      @environment = environment
      @outputs = {}
    end

    def fetch(name, *defaults)
      @environment.fetch(name, *defaults)
    end

    def directory
      value = fetch('RELEASE_DIRECTORY', nil)
      value unless value.to_s.empty?
    end

    def ref
      fetch('RELEASE_REF')
    end

    def git_identity
      { name: fetch('GIT_USER_NAME', 'ruby-gem-release'), email: fetch('GIT_USER_EMAIL', 'ruby-gem-release@localhost') }
    end

    def export(values)
      validate_values(values)
      @environment.update(values)
    end

    def output(values)
      validate_values(values)
      @outputs.update(values)
    end

    def context(**attributes)
      ExecutionContext.new(**attributes)
    end

    def step_id(task)
      ExecutionContext.step_id(task)
    end

    def failed_steps
      []
    end

    def oidc_token(audience:)
      raise NotImplementedError, 'execution provider does not support OIDC'
    end

    def mask(_value); end

    private

    def validate_values(values)
      raise ArgumentError, 'Workflow names must be identifiers' unless values.keys.all? { |name| name.is_a?(String) && /\A[A-Za-z_][A-Za-z0-9_]*\z/.match?(name) }
      raise ArgumentError, 'Workflow values cannot contain line breaks' if values.values.any? { |value| value.match?(/[\r\n]/) }
    end
  end
end
