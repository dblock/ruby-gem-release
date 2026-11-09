# frozen_string_literal: true

require 'ruby-gem-release/version/ruby_constant'

module GitLabSemanticReleaseExample
  class SemanticRelease
    def proceed?(ctx)
      version = version_for(ctx)
      return false if version.nil?

      raise ArgumentError, 'semantic release version must be MAJOR.MINOR.PATCH' unless version.is_a?(String) && RubyGemRelease::Version::RubyConstant::PATTERN.match?(version)

      ctx.workflow.provider.export('INPUT_VERSION' => version)
      true
    end

    def version_for(_ctx)
      raise NotImplementedError, 'Discover release history, analyze commits, and persist the selected version and generated notes'
    end
  end
end
