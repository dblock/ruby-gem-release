# Upgrading

Upgrade the gem and pinned workflow or action together. Apply the relevant changes below; see the linked PRs for details.

## Upgrading to 0.5.0 (Unreleased)

From 0.4.x, update both the gem and pinned Actions reference. Install only one workflow or manual task configuration.

### Callback and Command Changes

Before, inside `Tasks.install`:

```ruby
tasks.before_release { |release| puts release.version }
tasks.after_release { |release| puts release.version }
```

After:

```ruby
tasks.prepare { |ctx| puts ctx.release.version }
tasks.bump { |ctx| puts ctx.release.version }
```

Rename explicit Rake commands to `release:prepare` and `release:bump`; there are no aliases ([#30](https://github.com/dblock/ruby-gem-release/pull/30)). Real bump callbacks must still edit, commit, and push, then call `ctx.record_next_version!`. For complete wiring, use the [manual callback example](docs/usage.md#custom-callbacks).

Prepared-release test overrides change from:

```yaml
with:
  validate: bundle exec rake spec
```

To:

```yaml
with:
  test: bundle exec rake spec
```

`validate` checks preconditions before edits and fails when there is nothing to release. Custom commands must exit nonzero on invalid state; decision outputs are no longer read, and the `skipped` interface output is removed. Ruby callbacks raise on failure; normal completion, including `nil`, succeeds, while returning `false` also fails. Upgrade the gem and pinned interface together.

### Environment and Release Value Names

Update custom commands and provider environment hashes to use these names; there are no aliases ([#42](https://github.com/dblock/ruby-gem-release/pull/42)). Public workflow and action inputs such as `gemspec` and `rubygems-owner` are unchanged, as are standard GitHub, RubyGems, and reproducible-build variables.

| Previous name              | Replacement              |
| ---                        | ---                      |
| `INPUT_GEMSPEC`            | `INPUT_GEMSPEC_PATH`     |
| `GEMSPEC`                  | `GEMSPEC_PATH`           |
| `RELEASE_PREVIOUS_VERSION` | `GEMSPEC_VERSION`        |
| `RELEASE_INITIAL_COMMIT`   | `SOURCE_COMMIT`          |
| `RELEASE_REF`              | `SOURCE_REF`             |
| `RELEASE_DIRECTORY`        | `RELEASE_DATA_DIR`       |
| `RELEASE_STATE`            | `RELEASE_STATE_FILE`     |
| `RELEASE_AUTHENTICATION`   | `RELEASE_AUTH_MODE`      |
| `RELEASE_STEPS`            | `RELEASE_STEPS_JSON`     |
| `RELEASE_FAILURE_PHASE`    | `RELEASE_FAILED_STEP_ID` |
| `COMMAND`                  | `RELEASE_COMMAND`        |
| `RUBYGEMS_OWNER`           | `RUBYGEMS_OWNER_ID`      |

Rename `release.previous_version` to `release.gemspec_version` and the `Release.new` keyword `previous_version:` to `gemspec_version:`. The gemspec version is captured before release preparation, not the last published version; the source commit is the checkout commit hash captured at workflow start, not necessarily the later tagged commit. See [release values](docs/release.md#gemspec-version).

### Component Changes

- Capture defaults `SOURCE_DATE_EPOCH` to the committer timestamp of the original source commit, controlling the gemspec date and archive timestamps. Explicit values take precedence. Reruns must use the same source commit and build inputs; use the original epoch when reproducing older packages. See [package builds](docs/package/ruby_gem.md#build) and [#40](https://github.com/dblock/ruby-gem-release/pull/40).
- Release tasks must be idempotent for the same checkout and inputs, without recovery flags or state restoration. Actions configurations need a `workflow:` implementing `checkpoint!` before artifact preservation. Destinations need checksum-verified `published?(release, package:)`; version objects must accept `increment!(from:)` to anchor bumps to the release version, and default validation needs changelog `released?(version)` or a custom callback. Hosted metadata/assets are replaceable; Git tags and registry versions remain immutable. See [reruns](RELEASING.md#verify-and-recover) and [#40](https://github.com/dblock/ruby-gem-release/pull/40).
- Authentication is now part of `release:publish`, through the destination's `authenticate!(provider:)` hook; subclass `Destination` for its default that retains preconfigured credentials, or implement the hook on custom destination objects. RubyGems exchanges accept an optional owner and export credentials without creating or modifying `~/.gem/credentials`. Custom commands bypassing `release:publish` must own authentication; callbacks invoked by the task inherit its exported key variables. Authentication failures are reported under `publish_release`, not a separate authentication step. See [#36](https://github.com/dblock/ruby-gem-release/pull/36).
- Git and package objects now use `RELEASE_DATA_DIR` instead of `RUNNER_TEMP`; direct Git identity defaults are provider-neutral. Standard Actions behavior is unchanged. Inject `provider:` to replace execution services independently of hosting and registry destinations. See [#32](https://github.com/dblock/ruby-gem-release/pull/32).
- Move package version checks and publication to `Destination::RubyGems` using `check_version!(name:, version:)` and `publish!(release, package:)`. Configure `destination:` on the standard workflow, or pass `package:` and `destination:` to manual `Tasks.install`; custom packages now supply `name` as well. See [#31](https://github.com/dblock/ruby-gem-release/pull/31).
- Callback arguments are now execution contexts: replace `release.version` with `ctx.release.version`, and `failure.release` with `failure.context.release`. Use `ctx.step`, `steps`, `workflow`, and `run` for execution metadata; custom bump callbacks must call `ctx.record_next_version!` to propagate their next version. Rename `Workflow::Context` to `Workflow::Environment`. See [#31](https://github.com/dblock/ruby-gem-release/pull/31).
- Local callbacks receive `ExecutionContext` with a logical task ID and `run: nil`; GitHub Actions callbacks receive its `ExecutionContext::GitHub` subclass with Actions history and run metadata. See [#31](https://github.com/dblock/ruby-gem-release/pull/31).
- Empty pending notes and no releasable semantic commits now fail validation and invoke failure handling, replacing the successful skipping introduced in [#29](https://github.com/dblock/ruby-gem-release/pull/29). See [#40](https://github.com/dblock/ruby-gem-release/pull/40).

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
