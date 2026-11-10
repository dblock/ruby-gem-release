# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require_relative '../execution_provider'
require_relative '../execution_context/github'

module RubyGemRelease
  class ExecutionProvider
    class GitHub < ExecutionProvider
      def directory
        value = fetch('RUNNER_TEMP', nil)
        value unless value.to_s.empty?
      end

      def ref
        fetch('GITHUB_REF')
      end

      def git_identity
        { name: fetch('GIT_USER_NAME', 'github-actions[bot]'), email: fetch('GIT_USER_EMAIL', 'github-actions[bot]@users.noreply.github.com') }
      end

      def export(values)
        append_file('GITHUB_ENV', values)
        super
      end

      def context(**attributes)
        ExecutionContext::GitHub.new(**attributes, environment: @environment)
      end

      def step_id(task)
        ExecutionContext::GitHub.step_id(task, environment: @environment)
      end

      def failed_steps
        ExecutionContext::GitHub.steps(environment: @environment).select { |_id, step| step.outcome == 'failure' }.keys
      end

      def oidc_token(audience:)
        body = oidc_response(oidc_request(audience))
        token = body['value'] if body.is_a?(Hash)
        raise 'OIDC response did not contain a valid token' unless token.is_a?(String) && !token.empty? && !token.match?(/[\r\n]/)

        token
      end

      def mask(value)
        puts "::add-mask::#{value.gsub('%', '%25').gsub("\r", '%0D').gsub("\n", '%0A')}"
      end

      private

      def append_file(name, values)
        validate_values(values)
        File.open(fetch(name), 'a') { |file| values.each { |key, value| file.puts "#{key}=#{value}" } }
      end

      def oidc_request(audience)
        uri = URI(fetch('ACTIONS_ID_TOKEN_REQUEST_URL'))
        raise ArgumentError, 'OIDC request URL must use HTTPS' unless uri.is_a?(URI::HTTPS)

        query = URI.decode_www_form(uri.query || '').reject { |name, _value| name == 'audience' }
        uri.query = URI.encode_www_form(query + [['audience', audience]])
        Net::HTTP::Get.new(uri).tap { |request| request['Authorization'] = "Bearer #{fetch('ACTIONS_ID_TOKEN_REQUEST_TOKEN')}" }
      end

      def oidc_response(request)
        uri = request.uri
        result = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30, max_retries: 0) { |http| http.request(request) }
        raise "OIDC request failed (HTTP #{result.code})" unless result.is_a?(Net::HTTPSuccess)

        JSON.parse(result.body)
      rescue JSON::ParserError
        raise 'OIDC response was not valid JSON'
      end
    end
  end
end
