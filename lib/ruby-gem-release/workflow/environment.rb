# frozen_string_literal: true

require_relative '../package/ruby_gem'
require_relative '../destination/ruby_gems'
require_relative '../source_control/git'
require_relative '../release'
require_relative '../version/ruby_constant'
require_relative 'state'
require_relative '../execution_provider'

module RubyGemRelease
  module Workflow
    class Environment
      def initialize(provider: ExecutionProvider.current)
        @provider = provider
      end

      def configure!
        names = %w[INPUT_VERSION INPUT_GEMSPEC_PATH DEFAULT_BRANCH GIT_USER_NAME GIT_USER_EMAIL RUBYGEMS_OWNER_ID]
        timezone = @provider.fetch('TZ', 'UTC')
        validate_timezone(timezone)
        @provider.export(names.to_h { |name| [name, @provider.fetch(name)] }.merge('TZ' => timezone))
      end

      def capture!(package: nil)
        check_branch
        validate_timezone(@provider.fetch('TZ', 'UTC'))
        git = configured_git
        git.check_clean!
        package ||= Package::RubyGem.new(gemspec: @provider.fetch('INPUT_GEMSPEC_PATH', @provider.fetch('GEMSPEC_PATH', '')) || '', directory: @provider.directory)
        release = initial_release(package)
        git.check_current!(allow_ancestor: true)
        @provider.export(captured_values(package, git, release))
      end

      def resolve!(package: nil, destination: Destination::RubyGems.new, analysis: State.new(path: @provider.fetch('RELEASE_STATE_FILE', nil)).analysis)
        package ||= Package::RubyGem.new(gemspec: @provider.fetch('GEMSPEC_PATH', @provider.fetch('INPUT_GEMSPEC_PATH', '')) || '', directory: @provider.directory)
        authentication = authentication_for(destination)
        version = prepared_version(package, analysis)
        git = SourceControl::Git.new(directory: @provider.directory)
        git.stage_changes!
        @provider.export('RELEASE_VERSION' => version, 'RELEASE_AUTH_MODE' => authentication)
      end

      private

      def authentication_for(destination)
        authentication = destination.authentication
        raise ArgumentError, 'unsupported destination authentication' unless [nil, 'rubygems'].include?(authentication)

        authentication.to_s
      end

      def captured_values(package, git, release)
        commit = git.head
        state = State.create!(directory: @provider.directory) if @provider.directory
        { 'TZ' => @provider.fetch('TZ', 'UTC'), 'GEMSPEC_PATH' => package.respond_to?(:gemspec) ? package.gemspec.to_s : '', 'GEMSPEC_VERSION' => release.version,
          'RELEASE_DATA_DIR' => @provider.directory.to_s,
          'RELEASE_DATE' => release.date.iso8601, 'SOURCE_COMMIT' => commit, 'RELEASE_STATE_FILE' => state.to_s,
          'SOURCE_DATE_EPOCH' => source_date_epoch(git, commit) }
      end

      def source_date_epoch(git, commit)
        value = @provider.fetch('SOURCE_DATE_EPOCH', '').strip
        value.empty? ? git.timestamp(commit) : value
      end

      def prepared_version(package, analysis)
        version = package.version
        validate_version(version)
        analysis&.check!(head: @provider.fetch('SOURCE_COMMIT'), explicit_version: @provider.fetch('INPUT_VERSION', ''), version: version)
        selected = analysis ? analysis.version : @provider.fetch('INPUT_VERSION', '')
        raise "Prepared version #{version} does not match selected version #{selected}" unless selected.empty? || version == selected

        version
      end

      def initial_release(package)
        version = package.version
        validate_version(version)
        validate_version(@provider.fetch('INPUT_VERSION')) unless @provider.fetch('INPUT_VERSION', '').empty?
        Release.new(version: version, gemspec_version: version, date: release_date)
      end

      def release_date
        (@provider.fetch('TZ', nil) ? Time.now.getlocal : Time.now.utc).to_date
      end

      def validate_timezone(timezone)
        valid = %r{\A[A-Za-z0-9_+-]+(?:/[A-Za-z0-9_+-]+)*\z}.match?(timezone) &&
                File.file?(File.join('/usr/share/zoneinfo', timezone))
        raise ArgumentError, 'timezone must identify an installed timezone, such as UTC or America/New_York' unless valid
      end

      def configured_git
        SourceControl::Git.new(directory: @provider.directory).tap { |git| git.configure!(**@provider.git_identity) }
      end

      def check_branch
        return if @provider.ref == "refs/heads/#{@provider.fetch('DEFAULT_BRANCH')}"

        raise 'Releases must run from the default branch'
      end

      def validate_version(version)
        raise ArgumentError, 'Version must be MAJOR.MINOR.PATCH without leading zeros' unless Version::RubyConstant::PATTERN.match?(version)
      end
    end
  end
end
