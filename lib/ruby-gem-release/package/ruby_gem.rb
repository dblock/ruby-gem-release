# frozen_string_literal: true

require 'rubygems/package'
require 'open3'
require 'json'
require 'digest'
require 'fileutils'
require 'tmpdir'

module RubyGemRelease
  module Package
    class RubyGem
      attr_reader :gemspec

      def initialize(gemspec: nil, directory: nil, audit: nil)
        @gemspec = resolve_gemspec(gemspec || ENV.fetch('GEMSPEC_PATH', nil))
        directory ||= ENV.fetch('RELEASE_DATA_DIR', nil)
        @directory = directory unless directory.to_s.empty?
        @audit = audit
      end

      # Creates the default temporary directory only when artifacts are first used.
      def directory
        @directory ||= Dir.mktmpdir('ruby-gem-release-')
      end

      def version
        script = 'spec = Gem::Specification.load(ARGV.fetch(0)); abort "Cannot load gemspec" unless spec; puts JSON.generate(spec.version.to_s)'
        JSON.parse(run(Gem.ruby, '-rrubygems', '-rjson', '-e', script, @gemspec))
      end

      def build!(release)
        FileUtils.mkdir_p(directory)
        run({ 'SOURCE_DATE_EPOCH' => source_date_epoch }, Gem.ruby, '-S', 'gem', 'build', @gemspec, '--output', archive)
        @manifest = build_manifest(release)
        File.write(manifest_path, JSON.generate(@manifest))
        artifact(release)
      end

      def built?(release)
        return false unless File.exist?(archive) || File.exist?(manifest_path)

        verified_manifest(release)
        true
      end

      def artifact(release)
        manifest = verified_manifest(release)
        name = manifest.fetch('name')
        raise 'Invalid package name' unless /\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/.match?(name)

        platform = manifest.fetch('platform', 'ruby')
        raise 'Invalid package platform' unless /\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/.match?(platform)

        path = File.join(directory, Gem::Package.new(archive).spec.file_name)
        FileUtils.cp(archive, path)
        path
      end

      def artifacts(release)
        [artifact(release)]
      end

      private

      def source_date_epoch
        value = ENV.fetch('SOURCE_DATE_EPOCH', '').strip
        value.empty? ? '315619200' : value
      end

      def build_manifest(release)
        spec = Gem::Package.new(archive).spec
        raise "Built version #{spec.version} does not match #{release.version}" unless spec.version.to_s == release.version

        identity(spec).merge('sha256' => Digest::SHA256.file(archive).hexdigest)
      end

      def verified_manifest(release)
        manifest = @manifest || JSON.parse(File.read(manifest_path))
        raise 'Package version does not match release' unless manifest.fetch('version') == release.version
        raise 'Built artifact changed; refusing publication' unless Digest::SHA256.file(archive).hexdigest == manifest.fetch('sha256')

        verify_metadata!(manifest, release)
        @audit&.verify!(archive)
        manifest
      end

      def verify_metadata!(manifest, release)
        spec = Gem::Package.new(archive).spec
        expected = { 'name' => manifest.fetch('name'), 'version' => release.version, 'platform' => manifest.fetch('platform', 'ruby') }
        raise 'Artifact metadata differs from manifest' unless identity(spec) == expected
      end

      def identity(spec)
        { 'name' => spec.name, 'version' => spec.version.to_s, 'platform' => spec.platform.to_s }
      end

      def archive
        File.join(directory, 'release.gem')
      end

      def manifest_path
        File.join(directory, 'release.json')
      end

      def resolve_gemspec(path)
        paths = path.nil? || path.empty? ? Dir['*.gemspec'] : [path]
        raise ArgumentError, 'Expected exactly one root gemspec; specify gemspec' unless paths.one?
        raise ArgumentError, 'gemspec must name an existing file without line breaks' unless File.file?(paths.first) && !paths.first.match?(/[\r\n]/)

        File.expand_path(paths.first)
      end

      def run(*command)
        output, error, status = Open3.capture3(*command)
        raise "Package command failed: #{error.strip}\n#{output.strip}" unless status.success?

        output
      end
    end
  end
end
