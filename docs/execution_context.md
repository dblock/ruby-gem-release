# `RubyGemRelease::ExecutionContext`

The `ctx` passed to validation, preparation, publication, next development iteration, and success callbacks. Failure callbacks get a `ReleaseFailure` whose `context` works the same way. It gives access to release data, the workflow, and recorded state. It is a frozen snapshot, not a runner or a general data store.

```ruby
tasks.prepare do |ctx|
  puts ctx.step.id
  puts ctx.release.version
end
```

The [execution provider](execution_provider.md) creates contexts: [`ExecutionContext::GitHub`](execution_context/github.md) on Actions, this base class elsewhere, unless you pass a provider. The base knows nothing about GitHub; subclasses add platform details and providers do platform I/O.

## Release

`ctx.release` is the frozen [`Release`](release.md) used by changelog, package, Git, and hosting operations. It is `nil` in a failure callback if capture did not finish, and in hooks before capture. Other callbacks always have it.

## Lifecycle Stage

[Lifecycle hooks](workflow/hooks.md) get `ctx.stage`, `ctx.hook`, and `ctx.hook_index` (the stage, timing, and position). Failure hooks get the error as `ctx.failure`. Ordinary callbacks see `nil`.

## Step

In the base, `ctx.step.id` is the task name, such as `release:prepare`, and `ctx.steps` is empty because plain Rake has no step history. Subclasses supply real steps; [GitHub](execution_context/github.md#steps) reports outcome and conclusion separately.

Steps are a snapshot. Commit, build, tag, upload, and push inside publication are not separate steps.

## Workflow

`ctx.workflow` is the configured [`Workflow::RubyGem`](workflow/ruby_gem.md), with readers for `version`, `changelog`, `package`, `destination`, `git`, and `hosting`. These are the real objects, not copies; each process builds them from its Rakefile. With manual `Tasks.install` it is `nil` unless you pass `workflow:`. It is your Ruby configuration, not the Actions run or YAML.

## Run

`ctx.run` is `nil` in the base; see [GitHub Run](execution_context/github.md#run). Release operations never depend on the hosting platform.

## State

`ctx.record_next_version!(version)` saves the next development version for later callbacks, without changing earlier snapshots. The standard workflow records it only after the next-version commit is pushed; custom callbacks must record it themselves after success.

`ctx.analysis` is a frozen decision or `nil`. `ctx.record_analysis!(decision)` saves a validated `SemanticRelease::Decision` once. Standard semantic validation does this; manual workflows leave it unset. Recording `next_version` keeps the analysis.

On Actions, capture creates a private state file in `RUNNER_TEMP` and exports its path as `RELEASE_STATE_FILE`. It holds only `next_version` and an optional [semantic release decision](workflow/semantic_ruby_gem.md#state-and-callbacks) under `analysis`. Writes are atomic. Invalid versions, a missing or corrupt file, and unexpected or missing fields raise instead of resetting. Each capture gets its own file, even twice in one job. Failure reporting reads one snapshot; unreadable state is left out with a warning, keeping the original error.

Without a state file, callbacks of one `Tasks` object share state in memory within one process; separate processes do not. Custom shell commands must keep `RELEASE_STATE_FILE` and call the recording methods to pass values on.

## Failure

`failure.phase` names the failed step; `failure.context.step.id` names the running failure callback. `failure.error` is the captured exception, and its `stage`, `hook`, and `hook_index` name the failing stage or hook across processes, or are `nil` outside a lifecycle stage. Release data may be missing after an early failure, but step details remain. Failure callbacks cannot run before Ruby setup.
