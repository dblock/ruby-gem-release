# frozen_string_literal: true

require 'rubygems/package'
require 'open3'
require 'tmpdir'

module RubyGemRelease
  module Package
    class ContentAudit
      def initialize(expected_files:, source: 'HEAD', root: Dir.pwd, generated: [])
        @expected_files = expected_files
        @source = source
        @root = File.expand_path(root)
        @generated = checked_paths(generated)
      end

      def verify!(artifact)
        package = Gem::Package.new(artifact)
        expected = expected_paths
        raise 'Generated paths must be included in expected files' unless (@generated - expected).empty?

        actual = checked_paths(package.contents)
        raise "Archive file list differs: missing #{expected - actual}; unexpected #{actual - expected}" unless actual.sort == expected.sort

        source = git('rev-parse', '--verify', '--end-of-options', "#{@source}^{commit}").strip
        verify_files(package, expected, source)
        artifact
      end

      private

      def expected_paths
        checked_paths(@expected_files.respond_to?(:call) ? @expected_files.call : @expected_files)
      end

      def checked_paths(paths)
        raise ArgumentError, 'Expected an array of relative file paths' unless paths.is_a?(Array)
        raise ArgumentError, 'Duplicate file paths are not allowed' unless paths.uniq == paths

        paths.each do |path|
          raise ArgumentError, "Unsafe file path: #{path.inspect}" unless safe_path?(path)
        end
        paths
      end

      def safe_path?(path)
        path.is_a?(String) && !path.empty? && !path.match?(/[\x00\r\n\\]/) && !path.split('/', -1).intersect?(['', '.', '..'])
      end

      def verify_files(package, expected, source)
        Dir.mktmpdir('ruby-gem-release-audit-') do |directory|
          package.extract_files(directory)
          expected.each { |path| verify_file(directory, path, source) }
        end
      end

      def verify_file(directory, path, source)
        file = File.join(directory, path)
        raise "Archive entry must be a regular file: #{path}" unless File.file?(file) && !File.symlink?(file)
        return if @generated.include?(path)

        raise "Archive bytes differ from Git source: #{path}" unless File.binread(file) == git('show', "#{source}:#{path}").b
      end

      def git(*)
        output, error, status = Open3.capture3('git', '-C', @root, *)
        raise "Cannot verify Git source: #{error.strip}" unless status.success?

        output
      end
    end
  end
end
