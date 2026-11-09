# frozen_string_literal: true

require 'open3'
require 'json'

module RubyGemRelease
  class GitHubAPI
    def initialize(repository: nil)
      @repository = repository || '{owner}/{repo}'
    end

    def get(path)
      output, error, status = Open3.capture3('gh', 'api', '--include', endpoint(path))
      headers, body = output.split(/\r?\n\r?\n/, 2)
      code = headers.to_s[%r{\AHTTP/[\d.]+ (\d{3})}, 1]
      return if code == '404'
      raise "GitHub API request failed (HTTP #{code || 'unknown'}): #{error.strip}" unless status.success? && code == '200'

      JSON.parse(body)
    end

    def download(path)
      output, error, status = Open3.capture3('gh', 'api', endpoint(path), '--header', 'Accept: application/octet-stream')
      raise "GitHub asset download failed: #{error.strip}" unless status.success?

      output
    end

    private

    def endpoint(path)
      "repos/#{@repository}/#{path}"
    end
  end
end
