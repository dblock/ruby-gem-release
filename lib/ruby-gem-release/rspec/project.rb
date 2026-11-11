# frozen_string_literal: true

require 'fileutils'
require 'find'
require 'json'
require 'open3'
require 'pathname'

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

      def copy_files(path:, files: nil)
        source_root, destination_root = [path, @checkout].map { |directory| File.realpath(directory) }
        copies = selected_files(source_root, files).map do |file|
          source = copy_path(source_root, file)
          raise ArgumentError, "fixture source must be a regular file: #{file}" unless File.file?(source)

          [source, copy_path(destination_root, file)]
        end
        copies.each do |source, destination|
          FileUtils.mkdir_p(File.dirname(destination))
          FileUtils.copy_file(source, destination, true)
        end
      end

      def configure_workflow(require:, builder:)
        raise ArgumentError, 'workflow builder must be a constant path and method' unless builder.is_a?(String) && /\A(?:::)?[A-Z]\w*(?:::[A-Z]\w*)*\.[a-z_]\w*[!?]?\z/.match?(builder)

        source = workflow_source(require)
        write('Rakefile', <<~RUBY)
          require 'ruby-gem-release/rspec'
          require_relative #{source.dump}

          #{builder}(
            provider: RubyGemRelease::RSpec::Provider.new,
            destination: RubyGemRelease::RSpec::Destination.new,
            hosting: RubyGemRelease::RSpec::Hosting.new
          ).install_tasks
        RUBY
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

      def workflow_source(path)
        raise ArgumentError, 'workflow source must be a nonempty string' unless path.is_a?(String) && !path.empty?

        source = "#{path.delete_suffix('.rb')}.rb"
        root = File.realpath(@checkout)
        copy_path(root, source)
        copy_path(root, 'Rakefile')
        source
      end

      def selected_files(root, files)
        return source_files(root) if files.nil?

        available = nil
        Array(files).flat_map do |file|
          source = copy_path(root, file)
          pattern = source.delete_prefix("#{root}/")
          next pattern if File.exist?(source) || !pattern.match?(/[*?{\[]/)

          available ||= source_files(root)
          glob_files(pattern, available)
        end.uniq
      end

      def glob_files(pattern, available)
        matches = available.select { |file| File.fnmatch?(pattern, file, File::FNM_PATHNAME | File::FNM_DOTMATCH | File::FNM_EXTGLOB) }
        raise ArgumentError, "fixture source must match at least one regular file: #{pattern}" if matches.empty?

        matches
      end

      def source_files(root)
        Find.find(root).filter_map do |source|
          next if source == root

          Find.prune if File.basename(source) == '.git'

          source.delete_prefix("#{root}/") unless File.directory?(source) && !File.symlink?(source)
        end
      end

      def copy_path(root, path)
        path = File.path(path)
        candidate = File.expand_path(path, root)
        raise ArgumentError, 'fixture paths must be relative files inside their root' if Pathname.new(path).absolute? || !candidate.start_with?("#{root}/")

        ancestor = candidate
        ancestor = File.dirname(ancestor) until File.exist?(ancestor) || File.symlink?(ancestor)
        resolved = File.realpath(ancestor)
        raise ArgumentError, 'fixture paths must stay inside their root' unless resolved == root || resolved.start_with?("#{root}/")

        check_git_metadata(root, candidate, resolved)

        candidate
      end

      def check_git_metadata(root, *paths)
        return unless paths.any? { |path| path.delete_prefix("#{root}/").split('/').include?('.git') }

        raise ArgumentError, 'fixture files must not replace Git metadata'
      end

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
