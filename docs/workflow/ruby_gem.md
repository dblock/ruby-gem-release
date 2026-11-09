# `RubyGemRelease::Workflow::RubyGem`

Installs the standard Ruby gem release sequence through [`Tasks`](../tasks.md), using the existing package, source control, and hosting objects. See [Usage](../../README.md#usage) for the minimal setup or [Detailed Usage](../usage.md) for manual callbacks.

## Version

The required `version:` object implements `read` and `increment!`, plus `set!(value)` when a release version is selected. With an empty `version` input, preparation reads the checked-in version as before. With a selected version, preparation calls `set!` inside the trusted staging block before updating the changelog. The initial gemspec version remains `release.previous_version`; next development iteration preparation increments from the selected release version. The default [`RubyConstant`](../version/ruby_constant.md) increment is a patch change. Version files are never guessed.

## Changelog

The required `changelog:` object implements `release!(release)` and `prepare_next!(release)`. Choose [`KeepAChangelog`](../changelog/keep_a_changelog.md) or [`Intridea`](../changelog/intridea.md) explicitly. Set `changelog: nil` to skip changelog updates without skipping version incrementing.

The standard workflow registers `release:validate` to call `pending?` on the changelog before preparation. Empty pending notes skip the release successfully without edits or result callbacks; malformed changelog files fail. Pass `validate: ->(ctx) { ... }` to supply another decision, returning exactly `true` to proceed or `false` to skip. With `changelog: nil`, the default is to proceed. Custom changelog implementations must support `pending?` or supply a validation callback; the library does not guess their formats. Direct changelog `release!` calls still reject empty notes.

## Package

The optional `package:` defaults to [`Package::RubyGem`](../package/ruby_gem.md). It selects `GEMSPEC` or the only root gemspec and owns metadata, artifact construction, and verification. Override it with an object implementing `name`, `version`, `build!(release)`, and `artifact(release)`. Registry checks and uploads do not belong to the package.

## Destination

The optional `destination:` defaults to [`Destination::RubyGems`](../destination/ruby_gems.md). A registry destination implements `check_version!(name:, version:)`, `publish!(release, package:)`, and `authentication`. Subclass [`Destination`](../destination.md) to inherit the default of preconfigured credentials. No additional registry implementation is provided.

The same package and destination are supplied to prepared-version resolution and publication. Custom destinations therefore do not run the default RubyGems version checks or authentication. Destination publication must preserve exact-artifact identity and stop before the Git push on failure.

## Git

The optional `git:` defaults to [`SourceControl::Git`](../source_control/git.md). It implements `commit!`, `tag!`, `push!`, and `commit_next!`. Branch defaults come from the workflow environment or checkout. Default package and Git objects share the execution provider's directory. Git identity is configured during context capture; task installation alone does not alter Git configuration.

## Execution Provider

The optional `provider:` defaults to [`ExecutionProvider.current`](../execution_provider.md). It supplies inputs, environment and output transport, execution contexts, temporary storage, and platform-specific authentication services. The same provider is passed to the installed tasks and context checks. Execution providers do not select hosting or registry destinations; no GitLab implementation is included.

## Hosting

The optional `hosting:` defaults to [`Hosting::GitHubRelease`](../hosting/github_release.md), using the repository from Actions or the checkout. A custom object implements `publish!(release, package:)`. Set `hosting: nil` to disable hosted releases without disabling package publication or Git pushes.

## Install Tasks

`install_tasks` registers preparation, publication, next development iteration, success, failure, and workflow-context tasks. It does not immediately release or change project files. Use it instead of manual `Tasks.install` callback configuration, not alongside another installation.

Preparation updates the changelog with the explicitly read version. Publication checks the destination for the prepared version, commits release changes, builds once, tags locally, publishes the package through the destination, pushes the release commit and tag atomically, then publishes the hosted release. Next development iteration preparation increments the version, updates the changelog, passes the updated context to `commit_next!`, and pushes only the next development iteration commit.

Pass optional `success:` and `failure:` callbacks to the constructor for result notifications. Success receives an [ExecutionContext](../execution_context.md) with the published release and recorded next development version after the next development iteration succeeds. Failure receives a `RubyGemRelease::ReleaseFailure` with `phase`, `error`, and `context` properties; `failure.context.release` may be absent. A captured Ruby exception is reconstructed with its original class name, message, and stack trace; failures only reported by GitHub Actions have no `error`. A failure callback error does not turn a failed workflow into a successful one.

Callbacks can access this configured workflow through `ctx.workflow`. Public readers expose the configured `version`, `changelog`, `package`, `destination`, `git`, `hosting`, and `provider` objects; they are reconstructed through the Rakefile in each Ruby process, not serialized across Actions steps.

## Errors

Errors propagate through the tasks and stop the sequence. The default objects preserve concurrency checks, artifact verification, recovery bundles, and package-before-tag publication. Callbacks receive execution snapshots; the release value inside the failure context is `nil` if capture failed. Overrides must preserve the publication order and artifact identity.
