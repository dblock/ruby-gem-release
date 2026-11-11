# `RubyGemRelease::Workflow::RubyGem`

Installs the standard Ruby gem release sequence through [`Tasks`](../tasks.md), using the existing package, source control, and hosting objects. See [Usage](../../README.md#usage) for the minimal setup or [Detailed Usage](../usage.md) for manual callbacks.

## Version

The required `version:` object implements `read` and `increment!(from:)`, plus `set!(value)` when selecting a version. Bumps always calculate from `release.version`, so repetition writes the same next version. The default [`RubyConstant`](../version/ruby_constant.md) uses patch increments. The initial gemspec version remains `release.gemspec_version`.

## Changelog

The required `changelog:` object implements `release!(release)` and `prepare_next!(release)`. Choose [`KeepAChangelog`](../changelog/keep_a_changelog.md) or [`Intridea`](../changelog/intridea.md) explicitly. Set `changelog: nil` to skip changelog updates without skipping version incrementing.

Default validation requires `released?(release.version)` or `pending?`. This permits repetition after changelog preparation; otherwise empty pending notes raise before edits. Custom changelog objects must implement both queries or supply `validate: ->(ctx) { ... }`, raising on invalid state. Returning `false` also fails. With `changelog: nil`, validation passes. Direct `release!` calls reject empty notes unless that version already has a release heading.

## Package

The optional `package:` defaults to [`Package::RubyGem`](../package/ruby_gem.md), supplying capture, prepared-version checks, and reproducible builds. Implement `version`, `build!(release)`, `artifact(release)`, and `built?(release)` for equivalent verification and publication. `gemspec` remains optional for capture.

## Destination

The optional `destination:` defaults to [`Destination::RubyGems`](../destination/ruby_gems.md). A registry destination implements `authenticate!(provider:)`, `published?(release, package:)`, `publish!(release, package:)`, and `authentication`. Subclass [`Destination`](../destination.md) for the default credential-retaining authentication hook.

The same package and destination are supplied to prepared-version resolution and publication. Custom destinations therefore do not run the default RubyGems version checks or authentication. Destination publication must preserve exact-artifact identity and stop before the Git push on failure.

## Git

The optional `git:` defaults to [`SourceControl::Git`](../source_control/git.md). Custom objects implement `stage_changes!` (yielding to trusted edits), `commit!`, `tag!`, `push!`, and `commit_next!`. Defaults use the provider's directory and checkout branch. Capture separately configures and checks checkout-local Git; task installation does not alter Git configuration.

## Execution Provider

The optional `provider:` defaults to [`ExecutionProvider.current`](../execution_provider.md). It supplies inputs, environment transport, execution contexts, temporary storage, and platform-specific authentication services. The same provider is passed to the installed tasks and context checks. Execution providers do not select hosting or registry destinations; no GitLab implementation is included.

## Hosting

The optional `hosting:` defaults to [`Hosting::GitHubRelease`](../hosting/github_release.md). Custom objects implement idempotent `publish!(release, package:)`. Set `hosting: nil` to disable hosting without disabling registry publication or Git.

## Install Tasks

`install_tasks` registers preparation, publication, next development iteration, success, failure, and workflow-context tasks. It does not immediately release or change project files. Use it instead of manual `Tasks.install` callback configuration, not alongside another installation.

Preparation updates the changelog with the selected version. In Actions, the checkpoint commits, builds, and tags before artifacts are preserved. Publication then authenticates as needed, repeats those three operations, publishes the package, pushes the release commit and tag, and updates hosting. The next development iteration prepares, commits, and pushes the next version.

Pass optional `success:` and `failure:` callbacks for notifications. Success receives an execution context after the next development iteration completes; failure receives a `RubyGemRelease::ReleaseFailure`. Early failures may not have a release context, and failure callbacks do not turn a failed workflow into a successful one.

Contexts expose the configured `ctx.workflow`. Each process reconstructs the workflow from the Rakefile; it is not serialized across Actions steps.

## Lifecycle Hooks

Use `before(stage)` and `after(stage)` hooks to add checks or project edits without replacing callbacks. Preparation hooks run inside trusted Git staging. See the [hook guide](hooks.md) for ordering, safety, and an example.

## Errors

Errors stop the sequence. Default objects preserve concurrency checks, artifact verification, recovery bundles, and package-before-tag ordering. A failure context may not have a release if capture failed; custom operations must preserve publication order and artifact identity.
