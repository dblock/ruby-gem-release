# frozen_string_literal: true

require_relative 'ruby_gem'
require_relative '../source_control/reviewed_git'

module RubyGemRelease
  module Workflow
    class ReviewedRubyGem < RubyGem
      def initialize(package:, branches:, notes: nil, provider: ExecutionProvider.current, git: nil, **)
        git ||= SourceControl::ReviewedGit.new(branch: provider.ref.delete_prefix('refs/heads/'), branches: branches, directory: provider.directory)
        @notes = notes
        super(version: nil, changelog: nil, package: package, git: git, provider: provider, **)
      end

      def environment
        Environment.new(provider: @provider, source: @git)
      end

      private

      def verify_source!(release)
        @git.verify!(release, expected: @provider.fetch('SOURCE_COMMIT', @git.head))
      end

      def validate_release(ctx)
        verify_source!(ctx.release)
        publication_release(ctx.release)
        super
      end

      def prepare_release(ctx)
        run_stage(:prepare_release, ctx) { verify_source!(ctx.release) }
        verify_source!(ctx.release)
      end

      def prepare_publication(ctx)
        verify_source!(ctx.release)
        run_stage(:build_package, ctx) { @package.build!(ctx.release) }
        @git.preserve!(ctx.release, expected: @provider.fetch('SOURCE_COMMIT'))
      end

      def publish(ctx)
        release = publication_release(ctx.release)
        prepare_publication(ctx)
        run_stage(:publish_registry, ctx) { @destination.publish!(release, package: @package) }
        verify_source!(release)
        run_stage(:publish_hosted_release, ctx) { @hosting.publish!(release, package: @package) } if @hosting
      end

      def publication_release(release)
        return release unless @notes

        notes = @notes.read(release.version)
        raise ArgumentError, 'reviewed release notes must be a nonempty string' unless notes.is_a?(String) && !notes.strip.empty?

        Release.new(version: release.version, gemspec_version: release.gemspec_version, date: release.date, notes: notes)
      end

      def prepare_next(_ctx); end
    end
  end
end
