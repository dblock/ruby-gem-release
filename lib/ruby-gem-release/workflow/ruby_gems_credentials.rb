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

      CLAIMS = %w[repository job_workflow_ref environment].freeze

      def configure!
        key, = exchange!
        @provider.export(%w[RUBYGEMS_API_KEY BUNDLE_GEM__PUSH_KEY GEM_HOST_API_KEY].to_h { |name| [name, key] })
      end

      def check!
        _key, body, claims = exchange!
        scopes = body['scopes']
        raise 'Trusted publisher credential does not grant push_rubygem' unless scopes.is_a?(Array) && scopes.include?('push_rubygem')

        claims.merge('scopes' => scopes, 'expires_at' => body['expires_at'], 'owner' => body['owner']).compact
      end

      private

      def exchange!
        token = @provider.oidc_token(audience: 'rubygems.org')
        @provider.mask(token)
        claims = token_claims(token)
        body = exchange_token(token, claims)
        key = credential(body, 'rubygems_api_key')
        @provider.mask(key)
        [key, body, claims]
      end

      def token_claims(token)
        payload = JSON.parse(token.split('.')[1].to_s.tr('-_', '+/').unpack1('m'))
        payload.is_a?(Hash) ? payload.slice(*CLAIMS).select { |_name, value| value.is_a?(String) && !value.match?(/[\r\n]/) } : {}
      rescue JSON::ParserError
        {}
      end

      def exchange_token(token, claims)
        uri = URI('https://rubygems.org/api/v1/oidc/trusted_publisher/exchange_token')
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['Accept'] = 'application/json'
        body = { jwt: token }
        body[:owner] = @owner unless @owner.empty?
        request.body = JSON.generate(body)
        response(uri, request, claims)
      end

      def response(uri, request, claims)
        result = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30, max_retries: 0) do |http|
          http.request(request)
        end
        raise "Credential request failed (HTTP #{result.code}); #{publisher_hint(claims)}" unless result.is_a?(Net::HTTPSuccess)

        JSON.parse(result.body)
      rescue JSON::ParserError
        raise 'Credential response was not valid JSON'
      end

      def publisher_hint(claims)
        expected = claims.map { |name, value| "#{name} #{value}" }.join(', ')
        hint = 'verify trusted publisher configuration and owner ID if supplied'
        expected.empty? ? hint : "#{hint}; the token presented #{expected}"
      end

      def credential(body, name)
        value = body[name] if body.is_a?(Hash)
        raise 'Credential response did not contain a valid token' unless value.is_a?(String) && !value.empty? && !value.match?(/[\r\n]/)

        value
      end
    end
  end
end
