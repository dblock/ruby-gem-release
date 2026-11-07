# Working on `ruby-gem-release`

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [DESIGN.md](DESIGN.md) before making changes. This project will provide a reusable GitHub Actions release workflow and a Ruby gem with Rake tasks for common Ruby gem release operations; it is not a general-purpose release service.

The reusable workflow belongs in `.github/workflows/`, the gem API and Rake tasks belong in `lib/` and `tasks/`, and focused RSpec examples belong in `spec/`. Support Ruby 3.3 and newer; use public RubyGems, Rake, GitHub Actions, and RubyGems Trusted Publishing interfaces.

Keep release orchestration reusable while leaving project-specific preparation and version bump commands configurable by the calling repository. Test task behavior with focused unit tests and test the workflow through a real reusable-workflow consumer fixture; never claim workflow behavior is validated by unit tests alone.

Run `bundle exec rake` locally for specs and RuboCop before every push, and `bundle exec rake build` for package construction when applicable. Danger checks the changelog in PR CI, not as a routine local command. Document user-visible changes in `CHANGELOG.md`, listing entries within each release chronologically and keeping `- Your contribution here.` as the last entry in the next-release section; keep Markdown paragraphs on one source line.

The normal RuboCop command checks prose, Markdown Ruby examples, spelling, and YAML through `rubocop-prose`, `rubocop-md`, `rubocop-spellcheck`, and `rubocop-yaml`. Fix typos rather than suppressing checks; keep reviewed project vocabulary in `.spellcheck.txt` alongside the bundled English dictionary.

Preserve unrelated worktree changes. Use a separate worktree for each PR with a `dblock/<topic>` branch from `master`, keeping the primary checkout on `master` when clean. Keep one coherent commit per PR; amend it when making updates and use `git push --force-with-lease` for the topic branch when needed. Use squash or rebase merges, not merge commits. Ordinary development changes require PRs; explicitly authorized release automation may push release preparation and next-version commits directly without PRs. Never force-push to `master`. Do not merge, publish, or create release tags without authorization.

After a PR merges, clean up its local worktree and branch when no longer needed: verify the merged PR, inspect for uncommitted changes and dependent work, remove only clean worktrees, and delete the branch only when no work would be lost. Never discard changes to perform cleanup.
