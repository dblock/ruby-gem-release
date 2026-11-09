# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require_relative '../execution_provider'

module RubyGemRelease
  module Workflow
    class RubyGemsCredentials
      def initialize(owner: nil, provider: ExecutionProvider.current)
        @owner = owner.to_s
        raise ArgumentError, 'RubyGems owner must be a positive numeric account ID' unless @owner.empty? || /\A[1-9]\d*\z/.match?(@owner)

        @provider = provider
      end

      def configure!
        token = @provider.oidc_token(audience: 'rubygems.org')
        @provider.mask(token)
        key = exchange_token(token)
        @provider.mask(key)
        @provider.export(%w[RUBYGEMS_API_KEY BUNDLE_GEM__PUSH_KEY GEM_HOST_API_KEY].to_h { |name| [name, key] })
      end

      private

      def exchange_token(token)
        uri = URI('https://rubygems.org/api/v1/oidc/trusted_publisher/exchange_token')
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json'
        body = { jwt: token }
        body[:owner] = @owner unless @owner.empty?
        request.body = JSON.generate(body)
        credential(response(uri, request), 'rubygems_api_key')
      end

      def response(uri, request)
        result = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30, max_retries: 0) do |http|
          http.request(request)
        end
        raise "Credential request failed (HTTP #{result.code}); verify trusted publisher configuration and owner ID if supplied" unless result.is_a?(Net::HTTPSuccess)

        JSON.parse(result.body)
      rescue JSON::ParserError
        raise 'Credential response was not valid JSON'
      end

      def credential(body, name)
        value = body[name] if body.is_a?(Hash)
        raise 'Credential response did not contain a valid token' unless value.is_a?(String) && !value.empty? && !value.match?(/[\r\n]/)

        value
      end
    end
  end
end
