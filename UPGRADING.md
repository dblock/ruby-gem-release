# Upgrading

Upgrade the gem and pinned workflow or action together. Apply the relevant changes below; see the linked PRs for details.

## Upgrading to 0.5.0 (Unreleased)

- Move package version checks and publication to `Destination::RubyGems` using `check_version!(name:, version:)` and `publish!(release, package:)`. Configure `destination:` on the standard workflow, or pass `package:` and `destination:` to manual `Tasks.install`; custom packages now supply `name` as well. See [#31](https://github.com/dblock/ruby-gem-release/pull/31).
- Callback arguments are now execution contexts: replace `release.version` with `ctx.release.version`, and `failure.release` with `failure.context.release`. Use `ctx.step`, `steps`, `workflow`, and `run` for execution metadata; custom bump callbacks must call `ctx.record_next_version!` to propagate their next version. Rename `Workflow::Context` to `Workflow::Environment`. See [#31](https://github.com/dblock/ruby-gem-release/pull/31).
- Local callbacks receive `ExecutionContext` with a logical task ID and `run: nil`; GitHub Actions callbacks receive its `ExecutionContext::GitHub` subclass with Actions history and run metadata. See [#31](https://github.com/dblock/ruby-gem-release/pull/31).
- Rename `tasks.before_release` to `tasks.prepare` and `tasks.after_release` to `tasks.bump`. Update explicit Rake commands from `release:before_release` to `release:prepare` and `release:after_release` to `release:bump`; there are no compatibility aliases. The `prepare` and `bump` command input names are unchanged. See [#30](https://github.com/dblock/ruby-gem-release/pull/30).
- Move prepared-release test overrides from `validate:` to `test:`. The new `validate` command decides whether to release before preparation and must emit `proceed=true` or `proceed=false` to `GITHUB_OUTPUT`. See [#29](https://github.com/dblock/ruby-gem-release/pull/29).
- Empty pending changelog notes now skip successfully without publication or result callbacks. Custom changelog objects must implement `pending?` or supply a `validate:` callback returning `true` to proceed or `false` to skip. See [#29](https://github.com/dblock/ruby-gem-release/pull/29).

## Upgrading To 0.4.0

- The `version` input now selects the release version rather than only asserting it. Replace `RubyConstant#set` with `set!`; custom version objects and preparation commands must honor the selection. See [#26](https://github.com/dblock/ruby-gem-release/pull/26).
- Both built-in changelog formats reject empty notes on `release!`. Add actual notes; placeholders and structural Markdown do not count. See [#24](https://github.com/dblock/ruby-gem-release/pull/24).
- Already published RubyGems versions and version-lookup failures stop the release. Recover partial publication instead of blindly retrying. See [#25](https://github.com/dblock/ruby-gem-release/pull/25).

## Upgrading To 0.3.1

Keep the checkout clean after dependency setup; remove or intentionally ignore generated artifacts. Wrap custom preparation and next development iteration edits in `git.stage_changes!`. Publication rejects unrelated working-tree or index changes instead of staging them. See [#23](https://github.com/dblock/ruby-gem-release/pull/23).

## Upgrading To 0.3.0

Set `timezone` explicitly if you need a timezone other than the `UTC` default for release dates and Git timestamps. Use an installed named timezone such as `America/New_York`. See [#22](https://github.com/dblock/ruby-gem-release/pull/22).

## Upgrading To 0.2.3

Remove `dry-run` inputs, `dry_run` constructor arguments, and `release.dry_run?` checks. Dispatching requests real publication, not a preview; test and build locally first. See [#21](https://github.com/dblock/ruby-gem-release/pull/21).
