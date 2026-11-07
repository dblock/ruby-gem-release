# `RubyGemRelease::Tasks`

Registers optional preparation, publication, and next-version callbacks in the Rakefile. `Tasks.install` takes no arguments and yields the configuration object; it registers no version tasks and requires no version strategy. See [Detailed Usage](usage.md#custom-callbacks) for manual configuration or [the standard workflow](workflow/ruby_gem.md) to install the usual sequence.

## Install

Call `RubyGemRelease::Tasks.install` with a block to register callbacks. Without a block, all three callback tasks are registered and do nothing. It also registers `release:workflow:capture` and `release:workflow:resolve` for [Workflow::Context](workflow/context.md) context checks.

## Before Release

`tasks.before_release` prepares files before validation and publication. The callback receives an immutable [Release](release.md). Initially, `version` and `previous_version` contain the current gemspec version, and `next_version` is `nil`. Attach the prepared version with `release.with_version(version.read)` before updating a changelog if your callback changes it.

The default `prepare` command invokes `bundle exec rake release:before_release`. The task reads `RELEASE_PREVIOUS_VERSION` for both version fields and `RELEASE_DATE` from the environment.

## After Release

`tasks.after_release` prepares the next development version after publication. `version` contains the published version, `previous_version` retains the initial version, and `next_version` starts as `nil`. Explicitly increment the version and attach the result with `release.with_next_version(version.increment!)` before preparing the next changelog section.

The default `bump` command invokes `bundle exec rake release:after_release`. The task reads `RELEASE_VERSION`, `RELEASE_PREVIOUS_VERSION`, and `RELEASE_DATE` from the environment. Neither callback task changes versions implicitly. Configure `git.commit_next!(release)` and `git.push!` after your version and changelog edits.

## Errors and Dry Runs

Each callback requires a block and can be registered only once. Exceptions fail the task. All callbacks run in dry-run mode. `DRY_RUN=true` marks their context; the supplied classes suppress remote writes while performing local operations. Custom code remains trusted and must honor dry runs. Required environment values must contain numeric versions and a date in `YYYY-MM-DD` format; missing values fail rather than guessing a version or date.

## Publish

`tasks.publish` registers the complete release sequence before `after_release`. The default `publish` command invokes `bundle exec rake release:publish`, passing a [Release](release.md) built from `RELEASE_VERSION`, `RELEASE_PREVIOUS_VERSION`, `RELEASE_DATE`, and `DRY_RUN`.

The [Detailed Usage example](usage.md#custom-callbacks) commits, builds, tags, publishes to RubyGems, pushes atomically, and creates a GitHub Release. Without a callback, the task does nothing, including no package publication. To disable only GitHub Release creation, omit `github.publish!` while retaining the other operations.
