# `RubyGemRelease::Tasks`

Registers optional release callbacks in the Rakefile. `Tasks.install` takes no arguments and yields the configuration object; it registers no version tasks and requires no version strategy. See the [Usage example](../README.md#usage).

## Install

Call `RubyGemRelease::Tasks.install` with a block to register callbacks. Without a block, both callback tasks are registered and do nothing.

## Before Release

`tasks.before_release` prepares files before validation and publication. The callback receives an immutable [Release](release.md). Initially, `version` and `previous_version` contain the current gemspec version, and `next_version` is `nil`. Attach the prepared version with `release.with_version(version.read)` before updating a changelog if your callback changes it.

The default `prepare` command invokes `release:before_release[VERSION,PREVIOUS_VERSION,DATE]` with the initial version in both version arguments. A custom command can invoke it with `$RELEASE_PREVIOUS_VERSION,$RELEASE_PREVIOUS_VERSION,$RELEASE_DATE`.

## After Release

`tasks.after_release` prepares the next development version after publication. `version` contains the published version, `previous_version` retains the initial version, and `next_version` starts as `nil`. Explicitly increment the version and attach the result with `release.with_next_version(version.increment!)` before preparing the next changelog section.

The default `bump` command invokes `release:after_release[VERSION,PREVIOUS_VERSION,DATE]` with `$RELEASE_VERSION,$RELEASE_PREVIOUS_VERSION,$RELEASE_DATE`. Neither callback task changes versions implicitly.

## Errors and Dry Runs

Each callback requires a block and can be registered only once. Exceptions fail the task. Both callbacks run in dry-run mode, so they must be safe and trusted. Task arguments require numeric versions and a date in `YYYY-MM-DD` format.
