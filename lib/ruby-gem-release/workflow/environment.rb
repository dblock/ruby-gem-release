# frozen_string_literal: true

require_relative '../package/ruby_gem'
require_relative '../destination/ruby_gems'
require_relative '../source_control/git'
require_relative '../release'
require_relative '../version/ruby_constant'
require_relative 'state'

module RubyGemRelease
  module Workflow
    class Environment
      def configure!
        names = %w[INPUT_VERSION INPUT_GEMSPEC DEFAULT_BRANCH GIT_USER_NAME GIT_USER_EMAIL RUBYGEMS_OWNER]
        timezone = ENV.fetch('TZ', 'UTC')
        validate_timezone(timezone)
        export(names.to_h { |name| [name, ENV.fetch(name)] }.merge('TZ' => timezone))
      end

      def capture!
        check_branch
        validate_timezone(ENV.fetch('TZ', 'UTC'))
        git = configured_git
        git.check_clean!
        package = Package::RubyGem.new(gemspec: ENV.fetch('INPUT_GEMSPEC', nil))
        release = initial_release(package)
        git.check_current!(release)
        export(captured_values(package, git, release))
      end

      def resolve!(package: Package::RubyGem.new, destination: Destination::RubyGems.new)
        authentication = authentication_for(destination)
        version = prepared_version(package)
        git = SourceControl::Git.new
        git.check_tag!(version)
        destination.check_version!(name: package.name, version: version)
        git.stage_changes!
        export('RELEASE_VERSION' => version, 'RELEASE_AUTHENTICATION' => authentication)
      end

      private

      def authentication_for(destination)
        authentication = destination.authentication
        raise ArgumentError, 'unsupported destination authentication' unless [nil, 'rubygems'].include?(authentication)

        authentication.to_s
      end

      def captured_values(package, git, release)
        state = State.create!(directory: ENV.fetch('RUNNER_TEMP')) if ENV['RUNNER_TEMP']
        { 'TZ' => ENV.fetch('TZ', 'UTC'), 'GEMSPEC' => package.gemspec, 'RELEASE_PREVIOUS_VERSION' => release.version,
          'RELEASE_DATE' => release.date.iso8601, 'RELEASE_INITIAL_COMMIT' => git.head, 'RELEASE_STATE' => state.to_s }
      end

      def prepared_version(package)
        version = package.version
        validate_version(version)
        selected = ENV.fetch('INPUT_VERSION', '')
        raise "Prepared version #{version} does not match selected version #{selected}" unless selected.empty? || version == selected

        version
      end

      def initial_release(package)
        version = package.version
        validate_version(version)
        validate_version(ENV.fetch('INPUT_VERSION')) unless ENV.fetch('INPUT_VERSION', '').empty?
        Release.new(version: version, previous_version: version, date: release_date)
      end

      def release_date
        (ENV.key?('TZ') ? Time.now.getlocal : Time.now.utc).to_date
      end

      def validate_timezone(timezone)
        valid = %r{\A[A-Za-z0-9_+-]+(?:/[A-Za-z0-9_+-]+)*\z}.match?(timezone) &&
                File.file?(File.join('/usr/share/zoneinfo', timezone))
        raise ArgumentError, 'timezone must identify an installed timezone, such as UTC or America/New_York' unless valid
      end

      def configured_git
        SourceControl::Git.new.tap do |git|
          git.configure!(name: ENV.fetch('GIT_USER_NAME', 'github-actions[bot]'),
                         email: ENV.fetch('GIT_USER_EMAIL', 'github-actions[bot]@users.noreply.github.com'))
        end
      end

      def check_branch
        return if ENV.fetch('GITHUB_REF') == "refs/heads/#{ENV.fetch('DEFAULT_BRANCH')}"

        raise 'Releases must run from the default branch'
      end

      def validate_version(version)
        raise ArgumentError, 'Version must be MAJOR.MINOR.PATCH without leading zeros' unless Version::RubyConstant::PATTERN.match?(version)
      end

      def export(values)
        raise ArgumentError, 'Workflow values cannot contain line breaks' if values.values.any? { |value| value.match?(/[\r\n]/) }

        File.open(ENV.fetch('GITHUB_ENV'), 'a') do |file|
          values.each do |key, value|
            file.puts "#{key}=#{value}"
          end
        end
      end
    end
  end
end
