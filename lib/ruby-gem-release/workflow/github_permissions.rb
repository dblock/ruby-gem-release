# frozen_string_literal: true

require_relative '../github_api'
require_relative '../source_control/git'

module RubyGemRelease
  module Workflow
    # Checks that the job's GitHub token can push release commits and tags,
    # without sending any objects or changing refs.
    class GitHubPermissions
      BRANCH_BLOCKERS = %w[pull_request required_status_checks required_signatures update required_deployments merge_queue].freeze
      TAG_BLOCKERS = %w[creation required_signatures].freeze
      BYPASS = %w[always exempt].freeze

      def initialize(branch:, tag: nil, api: GitHubAPI.new, remote: 'origin')
        raise ArgumentError, 'a default branch is required to check GitHub permissions' if branch.to_s.empty?

        @branch = branch
        @tag = tag
        @api = api
        @remote = remote
      end

      def check!
        check_push!
        failures = blocked_branch_rules + blocked_tag_rules
        raise "GitHub rules would reject the release push: #{failures.join('; ')}" unless failures.empty?

        ["Verified GitHub push access to #{@branch}#{" and tag #{@tag}" if @tag}", *warnings]
      end

      private

      def check_push!
        SourceControl::Git.command('push', '--dry-run', '--porcelain', @remote, "HEAD:refs/heads/#{@branch}")
      rescue RuntimeError => e
        raise "GitHub token cannot push to #{@branch}; grant contents: write. #{e.message}"
      end

      def blocked_branch_rules
        rules = Array(@api.get("rules/branches/#{@branch}")).select { |rule| BRANCH_BLOCKERS.include?(rule['type']) }
        rules.group_by { |rule| rule['ruleset_id'] }.filter_map do |id, matched|
          ruleset = ruleset(id)
          blocked(ruleset, id, "branch #{@branch}", matched.map { |rule| rule['type'] }.uniq) unless bypass?(ruleset)
        end
      end

      def blocked_tag_rules
        return [] unless @tag

        Array(@api.get('rulesets?includes_parents=true&targets=tag')).filter_map do |summary|
          ruleset = ruleset(summary['id'])
          types = tag_blockers(ruleset)
          blocked(ruleset, summary['id'], "tag #{@tag}", types) unless types.empty? || bypass?(ruleset)
        end
      end

      def tag_blockers(ruleset)
        return [] unless ruleset && ruleset['enforcement'] == 'active' && matches?(ruleset, "refs/tags/#{@tag}")

        Array(ruleset['rules']).map { |rule| rule['type'] } & TAG_BLOCKERS
      end

      def ruleset(id)
        @api.get("rulesets/#{id}?includes_parents=true")
      end

      def bypass?(ruleset)
        ruleset && BYPASS.include?(ruleset['current_user_can_bypass'])
      end

      def matches?(ruleset, ref)
        names = ruleset.dig('conditions', 'ref_name') || {}
        included = Array(names['include']).any? { |pattern| pattern == '~ALL' || File.fnmatch?(pattern, ref) }
        included && Array(names['exclude']).none? { |pattern| File.fnmatch?(pattern, ref) }
      end

      def blocked(ruleset, id, ref, types)
        name = ruleset && ruleset['name']
        "#{ref}: #{name ? "ruleset #{name.inspect}" : "ruleset #{id}"} requires #{types.join(', ')}"
      end

      def warnings
        branch = @api.get("branches/#{@branch}")
        return [] unless branch.is_a?(Hash) && branch['protected']

        ["Warning: #{@branch} has branch protection; its push restrictions are not readable without admin access, so confirm the release token may push to it"]
      end
    end
  end
end
