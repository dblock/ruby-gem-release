# `RubyGemRelease::ExecutionContext`

Validation, preparation, publication, next development iteration, and success callbacks receive an execution context. Failure callbacks receive a `ReleaseFailure` whose `context` has the same interface. This provider-neutral base owns release data, workflow access, and explicit state recording. It is a frozen snapshot, not a workflow runner or a general-purpose mutable data store.

The configured [execution provider](execution_provider.md) constructs contexts. Automatic selection uses [`ExecutionContext::GitHub`](execution_context/github.md) on Actions and this base elsewhere; explicit provider injection overrides detection. The base does not read GitHub environment values or interpret Actions statuses. Provider-specific metadata and step details belong to subclasses; platform I/O belongs to execution providers.

```ruby
tasks.prepare do |ctx|
  puts ctx.step.id
  puts ctx.release.version
end
```

## Release

`ctx.release` is the immutable [`Release`](release.md) value used by changelog, package, Git, and hosting operations. It can be `nil` in a failure callback when release capture did not complete. Other callbacks require valid release data.

## Step

The base exposes a frozen step with the logical task ID, such as `release:prepare`. Its `steps` hash is empty because direct Rake invocation has no external execution history. Provider subclasses supply their current step and observed step snapshots; [GitHub](execution_context/github.md#steps) exposes Actions outcome and conclusion separately.

Execution history is a snapshot, not a record of operations inside a callback. Commit, build, tag, upload, and push remain operations inside publication, not separate tracked steps.

## Workflow

`ctx.workflow` is the configured [`Workflow::RubyGem`](workflow/ruby_gem.md) instance, with readers for `version`, `changelog`, `package`, `destination`, `git`, and `hosting`. These are the actual configured objects, not frozen or serialized copies. Each process constructs them normally through its Rakefile.

Manual `Tasks.install` leaves the workflow `nil` unless supplied explicitly with `workflow:`. The workflow reference describes Ruby configuration, not the Actions run or YAML.

## Run

`ctx.run` is `nil` in the base. Provider subclasses own their run metadata; see [GitHub Run](execution_context/github.md#run). Domain operations do not depend on a hosting provider or its environment.

## State

`ctx.record_next_version!(version)` explicitly records the next development version for later callbacks. Earlier snapshots are unchanged. Standard next development iteration preparation records it only after committing and pushing successfully. Custom callbacks must record it themselves after their operations succeed.

In Actions, environment capture creates a unique private state file in `RUNNER_TEMP` and exports its path as `RELEASE_STATE_FILE`. It contains only `next_version` and an optional [semantic release decision](workflow/semantic_ruby_gem.md#state-and-callbacks) under `analysis`. Arbitrary data and Ruby objects cannot be persisted. Writes are atomic and invalid versions, missing files, corrupt state, and unexpected or missing fields fail rather than being silently reset. Separate captures create separate files, including repeated action invocations in one job. Failure reporting uses one coherent snapshot, warning and omitting unreadable state while preserving the original exception and available execution metadata.

`ctx.analysis` is an immutable decision snapshot or `nil`. `ctx.record_analysis!(decision)` records a validated `SemanticRelease::Decision` exactly once for later tasks without changing existing snapshots. Standard semantic validation owns this operation; manual workflows leave analysis absent. Recording `next_version` does not replace analysis.

Without a state file, callbacks installed by the same `Tasks` instance share in-memory state within that Ruby process. Separate local processes do not share state automatically. Shell command overrides must preserve `RELEASE_STATE_FILE` and invoke the recording API if they need this propagation.

## Failure

`failure.phase` identifies the failed step, while `failure.context.step.id` identifies the currently executing failure callback. `failure.error` retains the captured exception interface. Release data may be absent, but execution metadata remains available after an early failure. Failure callbacks cannot run before Ruby setup completes.
