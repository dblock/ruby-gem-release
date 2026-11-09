# frozen_string_literal: true

require 'digest'
require_relative '../../github_api'

module RubyGemRelease
  module Hosting
    class GitHubRelease
      class Existing
        def initialize(repository:)
          @api = GitHubAPI.new(repository: repository)
        end

        def missing(release, paths)
          @attributes = @api.get("releases/tags/v#{release.version}")
          return paths unless @attributes

          validate_release(release)
          paths.reject { |path| matching_asset?(path) }
        end

        def exists?
          !@attributes.nil?
        end

        def url
          @attributes.fetch('html_url')
        end

        def changed?(release)
          expected = { 'name' => "v#{release.version}", 'draft' => false, 'prerelease' => false }
          expected['body'] = release.notes if release.notes
          expected.any? { |key, value| @attributes[key] != value }
        end

        private

        def validate_release(release)
          tag = "v#{release.version}"
          valid = @attributes.is_a?(Hash) && @attributes['tag_name'] == tag && @attributes['assets'].is_a?(Array)
          raise 'Existing GitHub Release conflicts with the intended release' unless valid
        end

        def matching_asset?(path)
          matches = @attributes.fetch('assets').select { |asset| asset['name'] == File.basename(path) }
          raise 'Existing GitHub Release has duplicate asset names' if matches.size > 1
          return false if matches.empty?

          asset_digest(matches.first) == Digest::SHA256.file(path).hexdigest
        end

        def asset_digest(asset)
          digest = asset['digest']
          return digest.delete_prefix('sha256:') if digest.is_a?(String) && /\Asha256:[0-9a-f]{64}\z/.match?(digest)

          id = asset['id']
          raise 'Existing GitHub asset cannot be verified' unless id.is_a?(Integer) && id.positive?

          Digest::SHA256.hexdigest(@api.download("releases/assets/#{id}"))
        end
      end
    end
  end
end
