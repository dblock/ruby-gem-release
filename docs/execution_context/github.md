# `RubyGemRelease::ExecutionContext::GitHub`

The `ctx` on GitHub Actions. It adds step results and run details to the base [`ExecutionContext`](../execution_context.md); release, workflow, and state work the same. The [GitHub execution provider](../execution_provider/github.md) creates it, including for failure callbacks.

## Steps

`ctx.step.id` is the running Actions step, from `RELEASE_STEP_ID`, or the task name if unset. Several Rake tasks in one custom command share it. The running step has no outcome yet.

`ctx.steps` is a frozen hash of steps by ID, each with `id`, `outcome` (the original result), and `conclusion` (after `continue-on-error`). Values are `success`, `failure`, `cancelled`, `skipped`, or `nil`. A missing entry means not seen, not skipped.

Both Actions interfaces pass a snapshot in `RELEASE_STEPS_JSON` before each configurable command. It is not live, has no later results, and may include other caller steps. Without it, `ctx.steps` is empty; invalid JSON raises. Outputs and credentials are not kept.

```ruby
tasks.prepare do |ctx|
  puts ctx.step.id
  puts ctx.steps['validate_release']&.outcome
end
```

## Run

`ctx.run` has frozen strings, or `nil` when unset, for `repository`, `ref`, `sha`, `run_id`, `run_attempt`, `job_id`, `workflow_name`, and `workflow_ref`. `sha` is the triggering commit, not necessarily `HEAD` after release commits. Tokens and event payloads are never copied.
