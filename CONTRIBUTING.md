# Contributing

Create a topic branch from `master` and keep each pull request focused on one coherent change.

Use a separate worktree for each PR with a `dblock/<topic>` branch, keeping the primary checkout on `master` when clean. Ordinary development changes go through PRs. Authorized release automation is an exception: release preparation and next development iteration commits may be pushed directly without PRs. The default-branch ruleset blocks force pushes and deletion but does not enforce PRs, allowing release automation and other writers to make fast-forward pushes.

After a PR merges, verify its merged state and check for uncommitted changes and dependent work before removing its clean, unneeded worktree and local branch. Do not discard work to clean up.

## Setup and Validation

Ruby 3.3 or newer is supported. Install dependencies with `bundle install`, run the specs and RuboCop locally with `bundle exec rake` before every push, and construct the gem with `bundle exec rake build` when applicable. Danger checks the changelog in PR CI rather than as a routine local command.

RuboCop includes Markdown prose checks with `rubocop-prose`, Ruby code block checks with `rubocop-md`, spelling checks with `rubocop-spellcheck`, and YAML checks with `rubocop-yaml`. Keep paragraphs on one source line, fix spelling mistakes, and add reviewed project vocabulary to `.spellcheck.txt`. Repository spelling checks cover comments and documentation, not Ruby strings; the standard license text is excluded from spelling and paragraph-length checks.

## Tests

RSpec examples live in `spec/`; add focused examples for release-task behavior and use real consumers to execute the reusable workflow and composite action's callback commands. Specs write HTML and LCOV coverage reports under `coverage/`, which CI uploads to Coveralls.

Run focused source tests with `bundle exec rake spec:unit`, which excludes `spec/integration/`. This includes in-process Rake coverage of documented configurations, timezone and version behavior, and lightweight YAML and shell-contract checks without creating consumer repositories. The Test workflow runs this task; installed-gem CI runs `bundle exec rake spec:integration` so consumer integration is not repeated against source in CI. `bundle exec rake spec` and the default task still run the complete suite locally.

Consumer integration specs live in `spec/integration/`. Keep a small real-process matrix covering both Actions interfaces' success, failure/recovery, skip, custom registry, and credential propagation. Preserve the provider-neutral consumers across separate processes: they verify environment transport, private state, and installed-library loading. Stub orchestration boundaries in focused specs, not these smoke tests. Existing domain specs cover detailed format, version, timezone, Git, and authentication edge cases without repeating whole release pipelines.

Profile integration examples with `bundle exec rake spec:integration SPEC_OPTS='--profile 15 --seed 12345'`. Compare before and after on the same machine and Ruby, including subprocess counts when changing the harness; do not enforce environment-dependent timing thresholds.

The release integration workflow builds and installs the actual gem, then exercises both interfaces' callback commands with real local Git pushes and isolated RubyGems and GitHub publication boundaries. Tests verify release and next development iteration commits, artifact identity, and publication ordering without publishing packages or creating hosted releases. They do not execute live Actions authentication or artifact uploading. Preserve authentication selection and failure-aware artifact upload when changing either interface. Validate workflow examples with `actionlint .github/workflows/*.yml examples/.github/workflows/*.yml`.

## Pull Requests

Keep one coherent commit per PR; amend updates and use `git push --force-with-lease` on the topic branch. Squash and rebase merges are supported; merge commits are disabled. Update affected documentation and append notable changes to the current Next changelog section with the PR link and author attribution, above `- Your contribution here.`. Keep Markdown paragraphs on one line. See [RELEASING.md](RELEASING.md).
