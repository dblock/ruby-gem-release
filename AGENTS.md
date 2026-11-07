# Working on ruby-gem-release

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [DESIGN.md](DESIGN.md) before making changes. This project will provide a reusable GitHub Actions release workflow and a Ruby gem with Rake tasks for common Ruby gem release operations; it is not a general-purpose release service.

The reusable workflow belongs in `.github/workflows/`, the gem API and Rake tasks belong in `lib/` and `tasks/`, and focused RSpec examples belong in `spec/`. Support Ruby 3.3 and newer; use public RubyGems, Rake, GitHub Actions, and RubyGems Trusted Publishing interfaces.

Keep release orchestration reusable while leaving project-specific preparation and version bump commands configurable by the calling repository. Test task behavior with focused unit tests and test the workflow through a real reusable-workflow consumer fixture; never claim workflow behavior is validated by unit tests alone.

Run `bundle exec rake` for specs and RuboCop, `bundle exec rake build` for package construction, and `bundle exec danger` for the changelog check. Document user-visible changes in `CHANGELOG.md`; keep Markdown paragraphs on one source line.

The normal RuboCop command checks prose, Markdown Ruby examples, and spelling through `rubocop-prose`, `rubocop-md`, and `rubocop-spellcheck`. Fix typos rather than suppressing checks; keep reviewed project vocabulary in `.spellcheck.txt` alongside the bundled English dictionary.

Preserve unrelated worktree changes. Work on topic branches from `master` and prefer one coherent commit for most PRs; multiple commits are welcome when they represent useful, independently reviewable changes. Use squash or rebase merges, not merge commits. Never commit or push directly to the default branch or force-push to `master`. Do not merge, publish, or create release tags without authorization.
