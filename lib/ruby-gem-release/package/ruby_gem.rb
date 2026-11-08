# frozen_string_literal: true

require 'rubygems/package'
require 'open3'
require 'json'
require 'digest'
require 'fileutils'
require 'tmpdir'
require 'net/http'
require 'uri'

module RubyGemRelease
  module Package
    class RubyGem
      attr_reader :directory, :gemspec

      def initialize(gemspec: nil, directory: nil)
        @gemspec = resolve_gemspec(gemspec || ENV.fetch('GEMSPEC', nil))
        @directory = directory || ENV['RUNNER_TEMP'] || Dir.mktmpdir('ruby-gem-release-')
      end

      def version
        specification.fetch('version')
      end

      def check_version!(version)
        name = specification.fetch('name')
        raise 'Invalid package name' unless name.is_a?(String) && /\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/.match?(name)

        check_published_version(name, version)
      end

      def build!(release)
        FileUtils.mkdir_p(@directory)
        run(Gem.ruby, '-S', 'gem', 'build', @gemspec, '--output', archive)
        @manifest = build_manifest(release)
        File.write(manifest_path, JSON.generate(@manifest))
        artifact(release)
      end

      def artifact(release)
        name = verified_manifest(release).fetch('name')
        raise 'Invalid package name' unless /\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/.match?(name)

        path = File.join(@directory, "#{name}-#{release.version}.gem")
        FileUtils.cp(archive, path)
        path
      end

      def publish!(release)
        path = artifact(release)
        check_published_version(verified_manifest(release).fetch('name'), release.version)
        run(Gem.ruby, '-S', 'gem', 'push', path)
      end

      private

      def specification
        script = 'spec = Gem::Specification.load(ARGV.fetch(0)); abort "Cannot load gemspec" unless spec; puts JSON.generate(name: spec.name, version: spec.version.to_s)'
        JSON.parse(run(Gem.ruby, '-rrubygems', '-rjson', '-e', script, @gemspec))
      end

      def check_published_version(name, version)
        response = version_response(name, version)
        raise "#{name} #{version} is already published on RubyGems; do not republish it, see RELEASING.md for recovery" if response.code == '200'
        return if response.code == '404'

        raise "Cannot check RubyGems for #{name} #{version} (HTTP #{response.code}); verify RubyGems availability before retrying"
      end

      def version_response(name, version)
        uri = URI("https://rubygems.org/api/v2/rubygems/#{URI.encode_www_form_component(name)}/versions/#{URI.encode_www_form_component(version)}.json")
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30, max_retries: 0) { |http| http.get(uri.request_uri) }
      rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => e
        raise "Cannot check RubyGems for #{name} #{version}: #{e.message}; verify connectivity before retrying"
      end

      def build_manifest(release)
        spec = Gem::Package.new(archive).spec
        raise "Built version #{spec.version} does not match #{release.version}" unless spec.version.to_s == release.version

        { 'name' => spec.name, 'version' => spec.version.to_s, 'sha256' => Digest::SHA256.file(archive).hexdigest }
      end

      def verified_manifest(release)
        manifest = @manifest || JSON.parse(File.read(manifest_path))
        raise 'Package version does not match release' unless manifest.fetch('version') == release.version
        raise 'Built artifact changed; refusing publication' unless Digest::SHA256.file(archive).hexdigest == manifest.fetch('sha256')

        manifest
      end

      def archive
        File.join(@directory, 'release.gem')
      end

      def manifest_path
        File.join(@directory, 'release.json')
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
