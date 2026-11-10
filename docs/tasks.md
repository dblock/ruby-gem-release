# `RubyGemRelease::Tasks`

Registers optional validation, preparation, publication, next development iteration, success, and failure callbacks in the Rakefile. `Tasks.install` accepts optional `workflow:`, `package:`, `destination:`, and `provider:` objects and yields the configuration object; it registers no version tasks and requires no version strategy. The package is resolved lazily when omitted, the destination defaults to RubyGems, and the [execution provider](execution_provider.md) is selected automatically. Pass the same package and destination used by manual publication callbacks so prepared-version checks and authentication agree. See [Detailed Usage](usage.md#custom-callbacks) for manual configuration or [the standard workflow](workflow/ruby_gem.md) to install the usual sequence.

## Install

Call `RubyGemRelease::Tasks.install` with a block to register callbacks. Without a block, validation proceeds and the other five callback tasks do nothing. Workflow tasks include `capture`, `resolve`, `checkpoint`, and `failure_phase`. Actions configurations must pass a configured `workflow:`: its checkpoint creates the archive, digest manifest, commit, and tag before artifact preservation and publication.

The composite action first invokes `release:workflow:configure` to validate and export its input environment for later steps. The reusable workflow supplies the same values through its job environment.

The provider constructs callback contexts: by default, the provider-neutral `ExecutionContext` locally or its [`GitHub`](execution_context/github.md) subclass on Actions. Explicit `provider:` injection overrides automatic detection. GitHub-specific step statuses and run fields are not part of the local context.

## Validate

`tasks.validate` checks release preconditions after context capture and before preparation edits. It receives an [ExecutionContext](execution_context.md) containing the same initial or explicitly selected release value as `prepare`. Raise on invalid state; normal completion, including `nil`, succeeds. Returning `false` also fails rather than skipping. Without a callback, validation passes.

Validation errors reach the failure callback with phase `validate_release`. Both Actions interfaces stop downstream release operations through normal failure handling; there is no decision output or successful skip. Separately invoked Rake tasks remain independent.

Every invocation runs the configured callbacks; there are no recovery flags or restored context. Default validation accepts the selected version's existing changelog section or pending notes; custom commands must provide equivalent idempotence:

```ruby
RubyGemRelease::Tasks.install do |tasks|
  tasks.validate { |_ctx| changelog.pending? }
end
```

## Prepare

`tasks.prepare` prepares files after release validation and before testing and publication. The callback receives an [ExecutionContext](execution_context.md); `ctx.release` is an immutable [Release](release.md). Its `version` contains the explicitly selected `INPUT_VERSION`, or the initial gemspec version when that input is empty. `gemspec_version` always retains the initial gemspec version, and `next_version` is `nil`. Custom callbacks own file updates; use your version object's `set!` method to honor a selection and attach the prepared version with `ctx.release.with_version(version.read)` before updating a changelog.

The default `prepare` command invokes `bundle exec rake release:prepare`. The task reads optional `INPUT_VERSION`, `GEMSPEC_VERSION`, and `RELEASE_DATE` from the environment. It validates the selected version before invoking the callback, but does not itself write a version file; the standard workflow callback does that through its configured object.

## Bump

`tasks.bump` prepares the next development iteration after publication. In `ctx.release`, `version` contains the published version and `gemspec_version` retains the initial version. Use `next_release = ctx.release.with_next_version(version.increment!(from: ctx.release.version))` before preparing the next changelog section, so repetition writes the same version rather than incrementing twice.

The default `bump` command invokes `bundle exec rake release:bump`. The task reads `RELEASE_VERSION`, `GEMSPEC_VERSION`, and `RELEASE_DATE` from the environment. Neither callback task changes versions implicitly. Configure `git.commit_next!(next_release)` and `git.push!` after your version and changelog edits; the commit context must include the incremented `next_version`.

After those operations succeed, call `ctx.record_next_version!(next_release.next_version)` to make the value available to later callbacks. The standard workflow does this automatically.

## Success and Failure

`tasks.success` runs only after publication and the next development iteration have succeeded. It receives an [ExecutionContext](execution_context.md) with the published release and recorded next development version. Use it for success notifications after the release commits are pushed.

The Actions interfaces invoke `tasks.failure` when release processing fails after Ruby and Bundler setup. It receives a `RubyGemRelease::ReleaseFailure` object with `phase`, `error`, and `context` properties. `context` is an execution context whose `release` can be `nil` after an early failure. `error` is a reconstructed `RubyGemRelease::ReleaseFailure::CapturedError` with the original exception class name, message, and stack trace when a Ruby task captured it; failures reported only by GitHub Actions have `error: nil`. The original job remains failed if the failure callback also raises.

`phase` is the failed GitHub Actions step ID, such as `publish_release`, or `unknown` when unavailable. It is distinct from `failure.context.step.id`, which identifies the failure callback itself. When multiple steps fail, the step with a captured Ruby exception is preferred; otherwise, one of the failed steps is reported without assuming execution order.

The reusable workflow and composite action run `bundle exec rake release:success` after a successful release and next development iteration, or `bundle exec rake release:failure` after a failed phase. Override the `success` or `failure` command input when a different command is needed. A failure before Ruby setup completes, or environment protection preventing the job from starting, cannot invoke the failure callback.

## Errors

Each registered callback requires a block and can be registered only once. Exceptions fail the task. Custom code executes with release privileges and must be trusted. Required environment values must contain numeric versions and a date in `YYYY-MM-DD` format; missing values fail rather than guessing a version or date.

## Publish

`tasks.publish` registers publication before `bump`. The default invokes `bundle exec rake release:publish` with the saved release context. It authenticates through the destination only when the workflow cannot verify an exact existing publication. Authentication exceptions are captured as publication failures; absent callbacks do not authenticate.

The [Detailed Usage example](usage.md#custom-callbacks) commits, builds, tags, publishes to RubyGems, pushes atomically, and creates a GitHub Release. Without a callback, the task does nothing, including no package publication. To disable only GitHub Release creation, omit `github.publish!` while retaining the other operations.

## Workflow Credentials

`release:workflow:credentials` directly invokes [`Workflow::RubyGemsCredentials`](workflow/ruby_gems_credentials.md) with optional `RUBYGEMS_OWNER_ID`. It remains available for custom RubyGems commands, but neither Actions interface calls a separate authentication task. Normal authentication belongs to `release:publish` through the configured destination.
