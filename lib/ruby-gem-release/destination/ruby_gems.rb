# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'open3'
require 'rubygems/package'
require_relative '../destination'

module RubyGemRelease
  class Destination
    class RubyGems < Destination
      def authentication
        'rubygems'
      end

      def check_version!(name:, version:)
        raise 'Invalid package name' unless name.is_a?(String) && /\A[A-Za-z0-9][A-Za-z0-9_.-]*\z/.match?(name)

        response = version_response(name, version)
        raise "#{name} #{version} is already published on RubyGems; do not republish it, see RELEASING.md for recovery" if response.code == '200'
        return if response.code == '404'

        raise "Cannot check RubyGems for #{name} #{version} (HTTP #{response.code}); verify RubyGems availability before retrying"
      end

      def publish!(release, package:)
        path = package.artifact(release)
        spec = Gem::Package.new(path).spec
        raise 'Package version does not match release' unless spec.version.to_s == release.version

        check_version!(name: spec.name, version: spec.version.to_s)
        push(path)
      end

      private

      def push(path)
        output, error, status = Open3.capture3(Gem.ruby, '-S', 'gem', 'push', path)
        raise "Destination command failed: #{error.strip}\n#{output.strip}" unless status.success?

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
