# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'open3'

module RubyGemRelease
  module RSpec
    class Project
      attr_reader :directory, :checkout, :remote, :environment

      def initialize(directory:)
        @directory = File.expand_path(directory)
        @checkout = File.join(@directory, 'checkout')
        @remote = File.join(@directory, 'remote.git')
        @environment = build_environment
        FileUtils.mkdir_p([@checkout, @environment.fetch('RELEASE_DATA_DIR')])
        initialize_git
      end

      def write(path, content)
        destination = File.expand_path(path, @checkout)
        raise ArgumentError, 'fixture files must be inside the checkout' unless destination.start_with?("#{@checkout}/")

        FileUtils.mkdir_p(File.dirname(destination))
        File.write(destination, content)
      end

      def commit!(message = 'Prepare release fixture')
        git('add', '.')
        git('commit', '--quiet', '-m', message)
        git('push', '--quiet', '-u', 'origin', 'master')
      end

      def git(*)
        output, error, status = Open3.capture3(@environment, 'git', *, chdir: @checkout, unsetenv_others: true)
        raise "#{output}\n#{error}" unless status.success?

        output.strip
      end

      def remote_file(ref, path)
        git('--git-dir', @remote, 'show', "#{ref}:#{path}")
      end

      def run_task(name, chdir: @checkout)
        output, error, status = Open3.capture3(@environment, Gem.ruby, '-S', 'bundle', 'exec', 'rake', name, chdir: chdir, unsetenv_others: true)
        import_environment
        return output if status.success?

        @environment['RELEASE_TEST_FAILURES'] = JSON.generate([name])
        raise "#{output}\n#{error}"
      end

      def release!(version: '', test_task: nil)
        @environment['INPUT_VERSION'] = version
        %w[release:workflow:capture release:validate release:prepare release:workflow:resolve].each { |name| run_task(name) }
        run_task(test_task) if test_task
        %w[release:workflow:checkpoint release:publish release:bump release:success].each { |name| run_task(name) }
      end

      private

      def initialize_git
        git('init', '--bare', '--quiet', '-b', 'master', @remote)
        git('init', '--quiet', '-b', 'master')
        git('config', 'user.name', 'Release Fixture')
        git('config', 'user.email', 'release-fixture@example.com')
        git('remote', 'add', 'origin', @remote)
      end

      def build_environment
        ENV.to_h.slice('PATH', 'HOME', 'TMPDIR', 'LANG').merge(
          ruby_environment,
          'GIT_CONFIG_NOSYSTEM' => '1', 'GIT_CONFIG_GLOBAL' => File::NULL,
          'RELEASE_DATA_DIR' => File.join(@directory, 'artifacts'),
          'RELEASE_TEST_ENVIRONMENT' => File.join(@directory, 'environment.json'),
          'SOURCE_REF' => 'refs/heads/master', 'DEFAULT_BRANCH' => 'master', 'TZ' => 'UTC'
        )
      end

      def ruby_environment
        {
          'BUNDLE_GEMFILE' => File.expand_path(ENV.fetch('RELEASE_CONSUMER_GEMFILE', ENV.fetch('BUNDLE_GEMFILE', 'Gemfile'))),
          'RUBYLIB' => ENV.fetch('RELEASE_CONSUMER_LIB', File.expand_path('../..', __dir__)),
          'GEM_HOME' => ENV.fetch('RELEASE_CONSUMER_GEM_HOME', Gem.dir),
          'GEM_PATH' => ENV.fetch('RELEASE_CONSUMER_GEM_PATH', Gem.path.join(File::PATH_SEPARATOR))
        }
      end

      def import_environment
        path = @environment.fetch('RELEASE_TEST_ENVIRONMENT')
        @environment.merge!(JSON.parse(File.read(path))) if File.file?(path)
      end
    end
  end
end
