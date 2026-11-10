# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'open3'
require 'rubygems/package'
require 'json'
require 'digest'
require_relative '../destination'
require_relative '../workflow/ruby_gems_credentials'

module RubyGemRelease
  class Destination
    class RubyGems < Destination
      def authenticate!(provider:)
        return unless provider.fetch('RELEASE_AUTH_MODE', '') == authentication

        Workflow::RubyGemsCredentials.new(owner: provider.fetch('RUBYGEMS_OWNER_ID', ''), provider: provider).configure!
      end

      def authentication
        'rubygems'
      end

      def publish!(release, package:)
        path = package.artifact(release)
        return if published?(release, package: package)

        push(path, release: release, package: package)
      end

      def published?(release, package:)
        path = package.artifact(release)
        spec = Gem::Package.new(path).spec
        raise 'Package version does not match release' unless spec.version.to_s == release.version

        matching_publication?(spec, path)
      end

      private

      def matching_publication?(spec, path)
        response = version_response(spec.name, spec.version.to_s)
        return false if response.code == '404'
        raise "Cannot verify RubyGems publication (HTTP #{response.code})" unless response.code == '200'

        metadata = JSON.parse(response.body)
        checksum = metadata['sha'] if metadata.is_a?(Hash)
        raise 'Published gem checksum differs or is unavailable; refusing to republish, see RELEASING.md for recovery' unless checksum == Digest::SHA256.file(path).hexdigest

        true
      end

      def push(path, release:, package:)
        output, error, status = Open3.capture3(Gem.ruby, '-S', 'gem', 'push', path)
        raise "Destination command failed: #{error.strip}\n#{output.strip}" unless status.success? || published?(release, package: package)

        output
      end

      def version_response(name, version)
        uri = URI("https://rubygems.org/api/v2/rubygems/#{URI.encode_www_form_component(name)}/versions/#{URI.encode_www_form_component(version)}.json")
        Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30, max_retries: 0) { |http| http.get(uri.request_uri) }
      rescue Timeout::Error, SocketError, SystemCallError, IOError, OpenSSL::SSL::SSLError => e
        raise "Cannot check RubyGems for #{name} #{version}: #{e.message}; verify connectivity before retrying"
      end
    end
  end
end
