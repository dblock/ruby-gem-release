# `RubyGemRelease::Tasks`

`Tasks` registers release callbacks as Rake tasks: validation, preparation, publication, next development version, success, and failure. [The standard workflow](workflow/ruby_gem.md) sets these up for you; use `Tasks` directly only to write your own callbacks, as in [Detailed Usage](usage.md#custom-callbacks).

`Tasks.install` yields a configuration object and takes these optional arguments:

- `workflow:`: the configured workflow. Required for Actions; see [Install](#install).
- `package:`: found automatically when omitted.
- `destination:`: RubyGems by default.
- `provider:`: the [execution provider](execution_provider.md), detected automatically.

It needs no version strategy. Pass the same package and destination your publication callbacks use, so version checks and authentication agree.

## Install

Register callbacks in the `RubyGemRelease::Tasks.install` block. Without a block, validation passes and the other five callback tasks do nothing. Workflow tasks include `capture`, `resolve`, `checkpoint`, and `failure_phase`. Actions setups must pass a configured `workflow:`, whose checkpoint creates the archive, digest manifest, commit, and tag before artifacts are saved and published.

The composite action first runs `release:workflow:configure` to check its inputs and export them for later steps. The reusable workflow sets the same values in its job environment.

The provider builds callback contexts: an `ExecutionContext` locally, or its [`GitHub`](execution_context/github.md) subclass on Actions. Passing `provider:` overrides detection. Step statuses and run details exist only on Actions.

Standard workflows also support [lifecycle hooks](workflow/hooks.md) for checks and file edits. Manual callbacks replace task behavior and do not get those hooks.

## Validate

`tasks.validate` checks release preconditions after capture and before any files are edited. It receives an [ExecutionContext](execution_context.md) with the same release version that `prepare` will get. Raise to fail. Returning normally, even `nil`, passes, but returning `false` fails. Without a callback, validation passes.

A validation error reaches the failure callback with phase `validate_release` and stops the release in both Actions interfaces. There is no "skip" result. Each Rake task you run by hand is independent.

Every run calls your callbacks again, with no recovery flags or restored context. Default validation accepts an existing changelog section for the version or pending notes, so reruns work; your callbacks must also be safe to rerun:

```ruby
RubyGemRelease::Tasks.install do |tasks|
  tasks.validate { |_ctx| changelog.pending? }
end
```

## Prepare

`tasks.prepare` edits files after validation and before tests and publication. It receives an [ExecutionContext](execution_context.md) whose `ctx.release` is an immutable [Release](release.md):

- `version` is `INPUT_VERSION` if set, otherwise the starting gemspec version.
- `gemspec_version` is always the starting gemspec version.
- `next_version` is `nil`.

Your callback makes the file changes. Apply a chosen version with your version object's `set!`, then pass `ctx.release.with_version(version.read)` to the changelog.

The default `prepare` command runs `bundle exec rake release:prepare`, which reads optional `INPUT_VERSION`, `GEMSPEC_VERSION`, and `RELEASE_DATE`. It checks the selected version before calling your callback, but never writes a version file itself.

## Bump

`tasks.bump` prepares the next development version after publication. `ctx.release.version` is the published version, and `gemspec_version` is the starting version. Compute the next version from the published one, so a rerun writes the same value instead of incrementing twice:

```ruby
next_release = ctx.release.with_next_version(version.increment!(from: ctx.release.version))
```

Then update the changelog and call `git.commit_next!(next_release)` and `git.push!`; the commit needs the new `next_version`. When those succeed, call `ctx.record_next_version!(next_release.next_version)` so later callbacks see it. The standard workflow does all of this.

The default `bump` command runs `bundle exec rake release:bump`, which reads `RELEASE_VERSION`, `GEMSPEC_VERSION`, and `RELEASE_DATE`. Neither task changes versions on its own.

## Success and Failure

`tasks.success` runs only after publication and the next development version succeed. It receives an [ExecutionContext](execution_context.md) with the published release and recorded next version. Use it for notifications.

The Actions interfaces call `tasks.failure` when the release fails after Ruby and Bundler are set up. It receives a `RubyGemRelease::ReleaseFailure` with:

- `phase`: the ID of the failed Actions step, such as `publish_release`, or `unknown`. This differs from `failure.context.step.id`, which is the failure callback's own step. When several steps fail, the one with a Ruby exception is reported; otherwise any failed step may be reported.
- `error`: a `RubyGemRelease::ReleaseFailure::CapturedError` with the original exception class name, message, and stack trace when a Ruby task caught it, or `nil` when only GitHub Actions reported the failure.
- `context`: an execution context. Its `release` can be `nil` after an early failure.

If the failure callback raises, the job still fails.

The reusable workflow and composite action run `bundle exec rake release:success` or `bundle exec rake release:failure`; override the `success` or `failure` input to change them. The failure callback cannot run if the job fails before Ruby setup completes or environment protection stops it from starting.

## Errors

Each callback needs a block and can be registered only once. An exception fails the task. Callbacks run with release permissions, so use only trusted code. Required environment values must hold numeric versions and a `YYYY-MM-DD` date; missing values fail rather than being guessed.

## Publish

`tasks.publish` registers publication, which runs before `bump`. The default command runs `bundle exec rake release:publish`. It authenticates through the destination unless the exact package is already published, and reports authentication errors as publication failures. Without a callback, nothing is authenticated or published.

The [Detailed Usage example](usage.md#custom-callbacks) commits, builds, tags, publishes to RubyGems, pushes commit and tag together, and creates a GitHub Release. To skip only the GitHub Release, leave out `github.publish!`.

## Workflow Credentials

`release:workflow:preflight` checks prerequisites without editing, pushing, or publishing:

- With a RubyGems destination, it checks Trusted Publishing through [`Workflow::RubyGemsCredentials#check!`](workflow/ruby_gems_credentials.md#check), using optional `RUBYGEMS_OWNER_ID`. Other destinations skip this check.
- On GitHub Actions, it checks that the token can push to `DEFAULT_BRANCH` and that no repository rule it cannot bypass would reject the release commit or the `vVERSION` tag. The version is `INPUT_VERSION` or the captured `GEMSPEC_VERSION`. Elsewhere this check is skipped.

Both Actions interfaces run preflight after capture; [dry runs](actions/release.md#dry-run) of the reusable workflow run only preflight.

`release:workflow:credentials` runs [`Workflow::RubyGemsCredentials`](workflow/ruby_gems_credentials.md) with optional `RUBYGEMS_OWNER_ID`, for custom RubyGems commands. The Actions interfaces do not call it; normal authentication happens in `release:publish`.
