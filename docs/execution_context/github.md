# `RubyGemRelease::ExecutionContext::GitHub`

Extends the provider-neutral [`ExecutionContext`](../execution_context.md) with GitHub Actions step snapshots and run metadata. The [GitHub execution provider](../execution_provider/github.md) constructs this subclass, including for failure callbacks. The inherited release, workflow, and state interface is unchanged.

## Steps

`ctx.step.id` identifies the enclosing Actions step, supplied explicitly through `RELEASE_STEP_ID`. A custom command invoking several Rake tasks retains that enclosing step identity. If the ID is unavailable, the logical task name is used instead. The current step has no final outcome or conclusion while it is executing.

`ctx.steps` is a frozen hash keyed by observed Actions step IDs. GitHub step objects expose `id`, `outcome`, `conclusion`, and frozen `outputs`. Outcome is the original result; conclusion reflects `continue-on-error`. Statuses are `success`, `failure`, `cancelled`, or `skipped`; missing values are `nil`. Missing entries mean unobserved, not skipped.

Both Actions interfaces supply a snapshot through `RELEASE_STEPS_JSON` before each configurable command. The snapshot is not live history, does not include future results, and may include other visible caller steps. If unavailable, it defaults to an empty hash. Invalid snapshots raise rather than inventing history. Only supported outputs are exposed; arbitrary action outputs and credentials are not retained.

```ruby
tasks.prepare do |ctx|
  puts ctx.step.id
  puts ctx.steps['validate_release']&.outcome
end
```

## Run

`ctx.run` exposes frozen copies of selected GitHub environment values: `repository`, `ref`, `sha`, `run_id`, `run_attempt`, `job_id`, `workflow_name`, and `workflow_ref`. Values remain strings; unavailable values are `nil`. `sha` identifies the triggering commit, not necessarily the checkout HEAD after release commits. No tokens or full GitHub event payloads are copied.

GitHub-specific environment parsing, run fields, status semantics, and supported output filtering live in this subclass and its step and run objects, not the shared base.
