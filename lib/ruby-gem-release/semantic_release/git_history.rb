# frozen_string_literal: true

require 'open3'
require_relative 'decision'

module RubyGemRelease
  class SemanticRelease
    class GitHistory
      def read(head:)
        check_head!(head)
        last_release = last_release(head)
        range = last_release ? "#{last_release.fetch('commit')}..#{head}" : head
        entries = run('log', '--reverse', '-z', '--format=%H%x00%B', range, '--').split("\0")
        commits = entries.each_slice(2).map { |sha, message| { 'sha' => sha, 'message' => message } }
        { last_release: last_release, commits: commits }
      end

      private

      def check_head!(head)
        raise ArgumentError, 'semantic history requires the captured commit SHA' unless head.is_a?(String) && Decision::SHA.match?(head)
        raise ArgumentError, 'semantic releases require a complete checkout; fetch full history and tags' if run('rev-parse', '--is-shallow-repository').strip == 'true'
        raise ArgumentError, 'checkout changed before semantic analysis' unless run('rev-parse', 'HEAD').strip == head
      end

      def last_release(head)
        tags = run('tag', '--merged', head).lines.map(&:strip)
        tags.select! { |tag| tag.start_with?('v') && Version::RubyConstant::PATTERN.match?(tag.delete_prefix('v')) }
        tag = tags.max_by { |candidate| Gem::Version.new(candidate.delete_prefix('v')) }
        return unless tag

        { 'tag' => tag, 'version' => tag.delete_prefix('v'), 'commit' => run('rev-parse', "refs/tags/#{tag}^{commit}").strip }
      end

      def run(*)
        output, error, status = Open3.capture3('git', *)
        raise "Semantic history Git command failed: #{error.strip}" unless status.success?

        output
      end
    end
  end
end
