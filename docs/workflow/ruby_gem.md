# `RubyGemRelease::Workflow::RubyGem`

`Workflow::RubyGem` installs the standard gem release tasks through [`Tasks`](../tasks.md). Only `version:` and `changelog:` are required. See [Usage](../../README.md#usage) for the minimal setup or [Detailed Usage](../usage.md) for manual callbacks.

## Version

The required `version:` object implements `read`, `set!(value)`, and `increment!(from:)`; construction fails if any is missing. The next version is always calculated from `release.version`, so a rerun writes the same value.

## Next Version

Optional `next_version:` picks the part to increment for the next development version: `:patch` (default), `:minor`, or `:major`, as a Symbol or String. For example, `next_version: :minor` starts `1.3.0` after releasing `1.2.0` or `1.2.1`.

`:patch` calls `increment!(from:)`; the others call `increment!(from:, part:)`, which [`RubyConstant`](../version/ruby_constant.md), [`PlainText`](../version/plain_text.md), and [`References`](../version/references.md) support. Construction fails for other values, or for `:minor` and `:major` when your `increment!` does not accept `part:`.

## Changelog

The required `changelog:` object implements `release!(release)` and `prepare_next!(release)`. Choose [`KeepAChangelog`](../changelog/keep_a_changelog.md) or [`Intridea`](../changelog/intridea.md). Set `changelog: nil` to skip changelog updates; the version is still incremented.

Default validation passes when the changelog has pending notes (`pending?`) or already has this version's section (`released?(release.version)`), so reruns work. It always passes with `changelog: nil`. A custom changelog must implement both queries, or you pass `validate: ->(ctx) { ... }`, which must raise on invalid state; returning `false` also fails. Calling `release!` directly fails on empty notes unless the version already has a release heading.

## Package

Optional `package:` defaults to [`Package::RubyGem`](../package/ruby_gem.md), which reads versions and builds reproducible gems. A custom package implements `version`, `build!(release)`, `artifact(release)`, and `built?(release)`; `gemspec` is optional.

## Destination

Optional `destination:` defaults to [`Destination::RubyGems`](../destination/ruby_gems.md). A registry destination implements `authenticate!(provider:)`, `published?(release, package:)`, `publish!(release, package:)`, and `authentication`. Subclass [`Destination`](../destination.md) for a default authentication hook that keeps existing credentials.

The same package and destination are used to check the prepared version and to publish, so a custom destination replaces the RubyGems checks and authentication. It must publish the exact built archive and raise on failure, so the Git push does not happen.

## Git

Optional `git:` defaults to [`SourceControl::Git`](../source_control/git.md) in the provider's directory and checked-out branch. A custom object implements `stage_changes!` (yielding to the file edits), `commit!`, `tag!`, `push!`, and `commit_next!`. Capture configures and checks Git in the checkout; installing tasks changes no Git configuration.

## Execution Provider

Optional `provider:` defaults to [`ExecutionProvider.current`](../execution_provider.md). It supplies inputs, passes values between steps, builds execution contexts, and provides temporary storage and platform authentication. It does not choose hosting or the registry. No GitLab provider is included.

## Hosting

Optional `hosting:` defaults to [`Hosting::GitHubRelease`](../hosting/github_release.md). A custom object implements `publish!(release, package:)`, which must be safe to repeat. Set `hosting: nil` to skip hosted releases while still publishing the gem and pushing to Git.

The hosted release uses the release's own notes when it has them, as semantic releases do. Otherwise it uses `changelog.notes(version)`, which both built-in formats implement. These notes are read before anything is published, so a missing or empty section fails before the gem is pushed. Without `notes`, or with `changelog: nil`, the platform generates the notes.

## Install Tasks

`install_tasks` registers the release tasks without running them or changing files. Use it instead of `Tasks.install` with manual callbacks, never both. A release runs these steps:

1. Preparation applies an explicit version, if given, and updates the changelog.
2. In Actions, a checkpoint commits, builds, and tags, then the artifacts are saved.
3. Publication authenticates if needed, repeats the commit, build, and tag, publishes the package, pushes the release commit and tag, and creates the hosted release.
4. The next development version is prepared, committed, and pushed.

Optional `success:` and `failure:` callbacks send notifications. `success` receives an execution context after the next version is pushed. `failure` receives a `RubyGemRelease::ReleaseFailure`, which may have no release after an early failure. A failure callback never makes a failed run succeed.

Contexts expose the workflow as `ctx.workflow`. Each process rebuilds it from the Rakefile.

## Lifecycle Hooks

Use `before(stage)` and `after(stage)` hooks to add checks or file edits without replacing callbacks. See the [hook guide](hooks.md).

## Errors

Any error stops the release. The default objects keep concurrency checks, artifact verification, recovery bundles, and build-before-tag order. If you replace an operation, keep the publication order and publish the exact built artifact.
