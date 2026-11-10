# Changelog

## 0.5.0 (Next)

- [#28](https://github.com/dblock/ruby-gem-release/pull/28): Add success callbacks and structured failure callbacks with captured Ruby exceptions to both Actions interfaces - [@dblock](https://github.com/dblock).
- [#29](https://github.com/dblock/ruby-gem-release/pull/29): Add release validation callbacks and successful skipping for empty pending notes, rename the prepared-release test command input from `validate` to `test` (breaking change), and document migration in [UPGRADING.md](UPGRADING.md) - [@dblock](https://github.com/dblock).
- [#30](https://github.com/dblock/ruby-gem-release/pull/30): Rename preparation and next development iteration callbacks and Rake tasks to `prepare` and `bump`, matching the Actions command inputs (breaking change) - [@dblock](https://github.com/dblock).
- [#31](https://github.com/dblock/ruby-gem-release/pull/31): Pass provider-specific execution contexts to callbacks with step history, workflow access, run metadata, and next development version propagation; separate registry destinations from package construction with a RubyGems implementation (breaking change) - [@dblock](https://github.com/dblock).
- [#32](https://github.com/dblock/ruby-gem-release/pull/32): Separate execution-platform services into a provider-neutral base and GitHub implementation, delegate environment and failure transport, and separate identity-token acquisition from the RubyGems exchange (breaking change) - [@dblock](https://github.com/dblock).
- [#33](https://github.com/dblock/ruby-gem-release/pull/33): Verify provider-neutral releases across separate consumer processes without Actions variables, group consumer specs under `spec/integration/` with a `spec:integration` Rake task, and guide README readers from defaults to workflow extensions - [@dblock](https://github.com/dblock).
- [#35](https://github.com/dblock/ruby-gem-release/pull/35): Add self-release and GitLab semantic-release customization walkthroughs with example-local placeholder providers - [@dblock](https://github.com/dblock).
- [#36](https://github.com/dblock/ruby-gem-release/pull/36): Move authentication into publication through destination hooks, remove registry-specific YAML steps, and unify RubyGems exchanges with optional owner binding and environment-only credentials; custom publication commands must not rely on a generated credentials file (breaking change) - [@dblock](https://github.com/dblock).
- [#38](https://github.com/dblock/ruby-gem-release/pull/38): Speed up release tests by separating focused orchestration coverage from real-process consumer smoke tests and avoiding duplicate source and installed integration runs in CI - [@dblock](https://github.com/dblock).
- [#37](https://github.com/dblock/ruby-gem-release/pull/37): Add opt-in semantic releases with reachable-tag history, configurable Conventional Commits rules and versions, persisted immutable decisions, generated notes and changelog files, and optional development bumps - [@dblock](https://github.com/dblock).
- [#39](https://github.com/dblock/ruby-gem-release/pull/39): Preserve configured packages during context capture, share workflow installation and coherent state snapshots, and streamline release and migration documentation - [@dblock](https://github.com/dblock).
- [#40](https://github.com/dblock/ruby-gem-release/pull/40): Make release tasks independently idempotent with source-commit timestamps, checksum-verified publication, reusable Git refs, and replaceable hosted notes/assets; fail empty-release validation and remove the decision-output protocol (breaking change) - [@dblock](https://github.com/dblock).
- [#41](https://github.com/dblock/ruby-gem-release/pull/41): Isolate release tests from inherited release context so this project's self-release can run its test suite - [@dblock](https://github.com/dblock).
- [#42](https://github.com/dblock/ruby-gem-release/pull/42): Standardize environment names into consistent input, gemspec, source, release, and registry families, and rename `release.previous_version` and its constructor keyword to `gemspec_version` to distinguish the captured gemspec version from release history (breaking change) - [@dblock](https://github.com/dblock).
- Your contribution here.

## 0.4.0 (2026/11/08)

- [#24](https://github.com/dblock/ruby-gem-release/pull/24): Reject empty release notes in both built-in changelog formats before writing release updates, ignoring placeholders, category headings, comments, and reference definitions - [@dblock](https://github.com/dblock).
- [#25](https://github.com/dblock/ruby-gem-release/pull/25): Reject existing RubyGems versions before release publication, stop on version lookup failures, and highlight release safeguards, recovery files, and timezone support in README - [@dblock](https://github.com/dblock).
- [#26](https://github.com/dblock/ruby-gem-release/pull/26): Select a release version with the existing version input, update it through the configured version object before preparation, and replace the version setter API with `set!` (breaking change) - [@dblock](https://github.com/dblock).
- [#27](https://github.com/dblock/ruby-gem-release/pull/27): Document maintainer-approved publication with protected GitHub environments and clarify dispatch permissions - [@dblock](https://github.com/dblock).

## 0.3.1 (2026/11/07)

- [#23](https://github.com/dblock/ruby-gem-release/pull/23): Reject dirty checkouts after dependency installation and commit only staged release preparation changes, preventing generated Bundler artifacts and unrelated files from entering releases - [@dblock](https://github.com/dblock).

## 0.3.0 (2026/11/07)

- [#22](https://github.com/dblock/ruby-gem-release/pull/22): Make the release timezone configurable with a UTC default, use Eastern Time for this project's releases, and prepare version 0.3.0 - [@dblock](https://github.com/dblock).

## 0.2.3 (2026/11/07)

- [#21](https://github.com/dblock/ruby-gem-release/pull/21): Remove dry-run inputs and release context, always publish when dispatched, and test installed release callbacks with isolated publication boundaries (breaking change) - [@dblock](https://github.com/dblock).

## 0.2.2 (2026/11/07)

- [#18](https://github.com/dblock/ruby-gem-release/pull/18): Update README release tags as part of the next development iteration - [@dblock](https://github.com/dblock).
- [#19](https://github.com/dblock/ruby-gem-release/pull/19): Use the incremented version in next development iteration commit messages and update terminology throughout workflows and documentation - [@dblock](https://github.com/dblock).

## 0.2.1 (2026/11/07)

- [#17](https://github.com/dblock/ruby-gem-release/pull/17): Avoid extra blank lines when releasing an empty changelog section and document release adoption and collaborator permissions - [@dblock](https://github.com/dblock).

## 0.2.0 (2026/11/07)

- [#15](https://github.com/dblock/ruby-gem-release/pull/15): Add a Marketplace-ready composite action sharing Ruby release tasks, document action setup and publication, and pin workflow examples to `v0.2.0` - [@dblock](https://github.com/dblock).
- [#16](https://github.com/dblock/ruby-gem-release/pull/16): Preserve release heading depths from `#` through `######` in both changelog formats, without reformatting consumer files - [@dblock](https://github.com/dblock).

## 0.1.0 (2026/11/07)

- [#2](https://github.com/dblock/ruby-gem-release/pull/2): Add reusable gem release workflow and version management Rake tasks - [@dblock](https://github.com/dblock).
- [#5](https://github.com/dblock/ruby-gem-release/pull/5): Add a ruby release logo - [@dblock](https://github.com/dblock).
- [#6](https://github.com/dblock/ruby-gem-release/pull/6): Add release callbacks for project-specific changelog updates - [@dblock](https://github.com/dblock).
- [#8](https://github.com/dblock/ruby-gem-release/pull/8): Add modular version and changelog updates, including comparison reference links, with a shared release context - [@dblock](https://github.com/dblock).
- [#9](https://github.com/dblock/ruby-gem-release/pull/9): Add package, Git, and GitHub Release classes with dry-run-aware publication callbacks, environment-based lifecycle tasks, configurable workflow commands, and Git commit identity inputs - [@dblock](https://github.com/dblock).
- [#10](https://github.com/dblock/ruby-gem-release/pull/10): Organize release classes, documentation, and tests by area; consolidate README configuration and add a reusable workflow reference - [@dblock](https://github.com/dblock).
- [#11](https://github.com/dblock/ruby-gem-release/pull/11): Add a standard Ruby gem workflow with explicit strategies and configurable objects, and move manual callback usage into detailed documentation - [@dblock](https://github.com/dblock).
- [#12](https://github.com/dblock/ruby-gem-release/pull/12): Explain release automation benefits and requirements, clarify version incrementing, simplify the caller example, and move configuration details out of README - [@dblock](https://github.com/dblock).
- [#13](https://github.com/dblock/ruby-gem-release/pull/13): Add a manual project release caller using the standard workflow, with dry runs enabled by default - [@dblock](https://github.com/dblock).
- [#14](https://github.com/dblock/ruby-gem-release/pull/14): Support owner-bound OIDC exchanges for first gem publication with pending trusted publishers - [@dblock](https://github.com/dblock).
