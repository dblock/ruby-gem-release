# `RubyGemRelease::Tasks`

Registers optional validation, preparation, publication, next development iteration, success, and failure callbacks in the Rakefile. `Tasks.install` takes no arguments and yields the configuration object; it registers no version tasks and requires no version strategy. See [Detailed Usage](usage.md#custom-callbacks) for manual configuration or [the standard workflow](workflow/ruby_gem.md) to install the usual sequence.

## Install

Call `RubyGemRelease::Tasks.install` with a block to register callbacks. Without a block, validation proceeds and the other five callback tasks do nothing. It also registers `release:workflow:capture`, `release:workflow:resolve`, and `release:workflow:failure_phase` for workflow context and failure checks.

The composite action first invokes `release:workflow:configure` to validate and export its input environment for later steps. The reusable workflow supplies the same values through its job environment.

## Validate

`tasks.validate` decides whether to release after context capture and before preparation edits. It receives the same initial or explicitly selected [Release](release.md) context as `prepare`. Return exactly `true` to proceed or `false` to skip successfully; missing or other return values raise an error. Exceptions fail the release and reach the failure callback with phase `validate_release`. Without a callback, validation proceeds.

The `release:validate` task prints the decision and, when `GITHUB_OUTPUT` is available, writes `proceed=true` or `proceed=false` for the Actions validation step. A successful skip gates all subsequent release steps, including tests, authentication, publication, artifact upload, next development iteration preparation, and the success callback. Neither result callback runs for a skip. The task itself does not prevent separately invoked Rake tasks from running.

The standard workflow registers a pending-changelog check automatically. Custom callbacks can use another read-only release decision:

```ruby
RubyGemRelease::Tasks.install do |tasks|
  tasks.validate { |_release| changelog.pending? }
end
```

## Prepare

`tasks.prepare` prepares files after release validation and before testing and publication. The callback receives an immutable [Release](release.md). `version` contains the explicitly selected `INPUT_VERSION`, or the initial gemspec version when that input is empty. `previous_version` always retains the initial gemspec version, and `next_version` is `nil`. Custom callbacks own file updates; use your version object's `set!` method to honor a selection and attach the prepared version with `release.with_version(version.read)` before updating a changelog.

The default `prepare` command invokes `bundle exec rake release:prepare`. The task reads optional `INPUT_VERSION`, `RELEASE_PREVIOUS_VERSION`, and `RELEASE_DATE` from the environment. It validates the selected version before invoking the callback, but does not itself write a version file; the standard workflow callback does that through its configured object.

## Bump

`tasks.bump` prepares the next development iteration after publication. `version` contains the published version, `previous_version` retains the initial version, and `next_version` starts as `nil`. Explicitly increment the version and retain the updated context with `next_release = release.with_next_version(version.increment!)` before preparing the next changelog section.

The default `bump` command invokes `bundle exec rake release:bump`. The task reads `RELEASE_VERSION`, `RELEASE_PREVIOUS_VERSION`, and `RELEASE_DATE` from the environment. Neither callback task changes versions implicitly. Configure `git.commit_next!(next_release)` and `git.push!` after your version and changelog edits; the commit context must include the incremented `next_version`.

## Success and Failure

`tasks.success` runs only after publication and the next development iteration have succeeded. It receives the published [Release](release.md) context. Use it for success notifications after the release commits are pushed.

The Actions interfaces invoke `tasks.failure` when release processing fails after Ruby and Bundler setup. It receives a `RubyGemRelease::ReleaseFailure` object with `phase`, `error`, and optional `release` properties. `error` is a reconstructed `RubyGemRelease::ReleaseFailure::CapturedError` with the original exception class name, message, and stack trace when a Ruby task captured it; failures reported only by GitHub Actions have `error: nil`. The original job remains failed if the failure callback also raises.

`phase` is the failed GitHub Actions step ID, such as `publish_release`, or `unknown` when unavailable. When multiple steps fail, the step with a captured Ruby exception is preferred; otherwise, one of the failed steps is reported without assuming execution order.

The reusable workflow and composite action run `bundle exec rake release:success` after a successful release and next development iteration, or `bundle exec rake release:failure` after a failed phase. Override the `success` or `failure` command input when a different command is needed. A failure before Ruby setup completes, or environment protection preventing the job from starting, cannot invoke the failure callback.

## Errors

Each registered callback requires a block and can be registered only once. Exceptions fail the task. Custom code executes with release privileges and must be trusted. Required environment values must contain numeric versions and a date in `YYYY-MM-DD` format; missing values fail rather than guessing a version or date.

## Publish

`tasks.publish` registers the complete release sequence before `bump`. The default `publish` command invokes `bundle exec rake release:publish`, passing a [Release](release.md) built from `RELEASE_VERSION`, `RELEASE_PREVIOUS_VERSION`, and `RELEASE_DATE`.

The [Detailed Usage example](usage.md#custom-callbacks) commits, builds, tags, publishes to RubyGems, pushes atomically, and creates a GitHub Release. Without a callback, the task does nothing, including no package publication. To disable only GitHub Release creation, omit `github.publish!` while retaining the other operations.

## Workflow Credentials

`release:workflow:credentials` invokes [`Workflow::RubyGemsCredentials`](workflow/ruby_gems_credentials.md) with `RUBYGEMS_OWNER`. The reusable workflow calls it for owner-bound publishing runs.
