# `RubyGemRelease::Workflow::RubyGem`

Installs the standard Ruby gem release sequence through [`Tasks`](../tasks.md), using the existing package, source control, and hosting objects. See [Usage](../../README.md#usage) for the minimal setup or [Detailed Usage](../usage.md) for manual callbacks.

## Version

The required `version:` object implements `read` and `increment!`, plus `set!(value)` when a release version is selected. With an empty `version` input, preparation reads the checked-in version as before. With a selected version, preparation calls `set!` inside the trusted staging block before updating the changelog. The initial gemspec version remains `release.previous_version`; next development iteration preparation increments from the selected release version. The default [`RubyConstant`](../version/ruby_constant.md) increment is a patch change. Version files are never guessed.

## Changelog

The required `changelog:` object implements `release!(release)` and `prepare_next!(release)`. Choose [`KeepAChangelog`](../changelog/keep_a_changelog.md) or [`Intridea`](../changelog/intridea.md) explicitly. Set `changelog: nil` to skip changelog updates without skipping version incrementing.

The standard workflow registers `release:validate` to call `pending?` on the changelog before preparation. Empty pending notes skip the release successfully without edits or result callbacks; malformed changelog files fail. Pass `validate: ->(release) { ... }` to supply another decision, returning exactly `true` to proceed or `false` to skip. With `changelog: nil`, the default is to proceed. Custom changelog implementations must support `pending?` or supply a validation callback; the library does not guess their formats. Direct changelog `release!` calls still reject empty notes.

## Package

The optional `package:` defaults to [`Package::RubyGem`](../package/ruby_gem.md). It selects `GEMSPEC` or the only root gemspec and owns artifact construction, verification, and publication. Override it with an object implementing `check_version!(version)`, `build!(release)`, and `publish!(release)`, plus `artifact(release)` when required by your hosting object. The version check is a required new method for custom package objects; it must reject already published versions before any release commit. The default implementation checks public RubyGems.

## Git

The optional `git:` defaults to [`SourceControl::Git`](../source_control/git.md). It implements `commit!`, `tag!`, `push!`, and `commit_next!`. Branch and artifact-directory defaults come from the workflow environment or checkout. Git identity is configured by the Actions context checks; task installation alone does not alter Git configuration.

## Hosting

The optional `hosting:` defaults to [`Hosting::GitHubRelease`](../hosting/github_release.md), using the repository from Actions or the checkout. A custom object implements `publish!(release, package:)`. Set `hosting: nil` to disable hosted releases without disabling package publication or Git pushes.

## Install Tasks

`install_tasks` registers preparation, publication, next development iteration, success, failure, and workflow-context tasks. It does not immediately release or change project files. Use it instead of manual `Tasks.install` callback configuration, not alongside another installation.

Preparation updates the changelog with the explicitly read version. Publication checks RubyGems for the prepared version, commits release changes, builds once, tags locally, publishes the package, pushes the release commit and tag atomically, then publishes the hosted release. Next development iteration preparation increments the version, updates the changelog, passes the updated context to `commit_next!`, and pushes only the next development iteration commit.

Pass optional `success:` and `failure:` callbacks to the constructor for result notifications. Success receives the published release context after the next development iteration succeeds. Failure receives a `RubyGemRelease::ReleaseFailure` with `phase`, `error`, and optional `release` properties. A captured Ruby exception is reconstructed with its original class name, message, and stack trace; failures only reported by GitHub Actions have no `error`. A failure callback error does not turn a failed workflow into a successful one.

## Errors

Errors propagate through the tasks and stop the sequence. The default objects preserve concurrency checks, artifact verification, recovery bundles, and package-before-tag publication. Preparation, publication, next-development-iteration, and success callbacks receive an immutable release context; the failure callback receives it when available, or `nil` if context capture failed. Overrides must preserve the publication order and artifact identity.
