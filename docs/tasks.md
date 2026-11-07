# `RubyGemRelease::Tasks`

Registers optional preparation, publication, and next-version callbacks in the Rakefile. `Tasks.install` takes no arguments and yields the configuration object; it registers no version tasks and requires no version strategy. See the [Usage example](../README.md#usage).

## Install

Call `RubyGemRelease::Tasks.install` with a block to register callbacks. Without a block, all three callback tasks are registered and do nothing.

## Before Release

`tasks.before_release` prepares files before validation and publication. The callback receives an immutable [Release](release.md). Initially, `version` and `previous_version` contain the current gemspec version, and `next_version` is `nil`. Attach the prepared version with `release.with_version(version.read)` before updating a changelog if your callback changes it.

The default `prepare` command invokes `bundle exec rake release:before_release`. The task reads `RELEASE_PREVIOUS_VERSION` for both version fields and `RELEASE_DATE` from the environment.

## After Release

`tasks.after_release` prepares the next development version after publication. `version` contains the published version, `previous_version` retains the initial version, and `next_version` starts as `nil`. Explicitly increment the version and attach the result with `release.with_next_version(version.increment!)` before preparing the next changelog section.

The default `bump` command invokes `bundle exec rake release:after_release`. The task reads `RELEASE_VERSION`, `RELEASE_PREVIOUS_VERSION`, and `RELEASE_DATE` from the environment. Neither callback task changes versions implicitly.

## Errors and Dry Runs

Each callback requires a block and can be registered only once. Exceptions fail the task. Preparation and next-version callbacks run in dry-run mode, so they must be safe and trusted; the workflow skips publication. Required environment values must contain numeric versions and a date in `YYYY-MM-DD` format; missing values fail rather than guessing a version or date.

## Publish

`tasks.publish` registers remote publication work after RubyGems publication and the remote tag push, before `after_release`. The default `github-release` command invokes `bundle exec rake release:publish`, passing a [Release](release.md) built from `RELEASE_VERSION`, `RELEASE_PREVIOUS_VERSION`, and `RELEASE_DATE`.

The [Usage example](../README.md#usage) copies the exact preserved gem to its package filename and invokes [`GitHubRelease`](github_release.md). Without a callback, the task does nothing. The workflow skips this entire step in dry-run mode; calling the task directly executes the callback and is not dry-run-aware. RubyGems publication and artifact building remain workflow operations.
