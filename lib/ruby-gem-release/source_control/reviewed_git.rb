# frozen_string_literal: true

require_relative 'git'

module RubyGemRelease
  module SourceControl
    # Read-only source control for already reviewed, signed releases. Wraps a
    # Git checkout and exposes no operations that commit, tag, stage, or push.
    class ReviewedGit
      def initialize(branch:, branches:, remote: 'origin', directory: nil)
        raise ArgumentError, 'branches must be a nonempty array of explicit branch names' unless branches.is_a?(Array) && !branches.empty?

        branches.each { |name| Git.command('check-ref-format', '--branch', name) }
        @branch = branch
        @branches = branches.dup.freeze
        @remote = remote
        @git = Git.new(branch: branch, remote: remote, directory: directory)
      end

      def head
        @git.head
      end

      def timestamp(commit)
        @git.timestamp(commit)
      end

      def configure!(**)
        @git.configure!(**)
      end

      def check_clean!
        @git.check_clean!
      end

      def check_branch!(ref:)
        return if @branches.include?(@branch) && ref == "refs/heads/#{@branch}"

        raise 'Reviewed releases must run from an explicitly allowed branch'
      end

      # Reviewed sources must be at the exact remote tip; callers' ancestor
      # allowances, such as capture's, do not apply.
      def check_current!(expected: head, **)
        @git.check_current!(expected: expected, allow_ancestor: false)
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
        @git.write_bundle(release)
      end

      private

      def verify_tag!(release)
        ref = "refs/tags/v#{release.version}"
        raise 'Reviewed release requires an existing tag at the checkout commit' unless @git.tag_commit(release.version) == head

        object = Git.command('rev-parse', ref).strip
        remote = Git.command('ls-remote', '--refs', @remote, ref).split
        raise 'Reviewed release tag must match the exact existing remote tag' unless remote == [object, ref]

        Git.command('verify-tag', ref)
      end
    end
  end
end
