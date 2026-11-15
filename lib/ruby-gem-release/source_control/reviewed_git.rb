# frozen_string_literal: true

require_relative 'git'

module RubyGemRelease
  module SourceControl
    class ReviewedGit < Git
      def initialize(branch:, branches:, **)
        super(branch: branch, **)
        raise ArgumentError, 'branches must be a nonempty array of explicit branch names' unless branches.is_a?(Array) && !branches.empty?

        branches.each { |name| run('check-ref-format', '--branch', name) }
        @branches = branches.dup.freeze
      end

      def check_branch!(ref:)
        return if @branches.include?(branch) && ref == "refs/heads/#{branch}"

        raise 'Reviewed releases must run from an explicitly allowed branch'
      end

      def check_current!(expected: head, **)
        super(expected: expected, allow_ancestor: false)
      end

      def verify!(release, expected: head)
        raise 'Reviewed checkout differs from captured source commit' unless head == expected

        check_clean!
        check_current!(expected: expected)
        verify_tag!(release)
        head
      end

      def preserve!(release, expected: head)
        verify!(release, expected: expected)
        write_bundle(release)
      end

      private

      def verify_tag!(release)
        ref = "refs/tags/v#{release.version}"
        raise 'Reviewed release requires an existing tag at the checkout commit' unless tag_commit(release.version) == head

        object = run('rev-parse', ref).strip
        remote = run('ls-remote', '--refs', @remote, ref).split
        raise 'Reviewed release tag must match the exact existing remote tag' unless remote == [object, ref]

        run('verify-tag', ref)
      end
    end
  end
end
