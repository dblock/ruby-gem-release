# Lifecycle Hooks

Hooks run your code before or after a release stage in the [standard](ruby_gem.md), [semantic](semantic_ruby_gem.md), and [reviewed](reviewed_ruby_gem.md) workflows. Register them before `install_tasks`:

```ruby
workflow.before(:validate) { |ctx| validate_project_notes(ctx) }
workflow.after(:prepare_release) { |ctx| update_stable_readme(ctx) }
workflow.after(:prepare_next) { |ctx| update_development_readme(ctx) }

workflow.install_tasks
```

Each stage runs its before hooks, the built-in step, then its after hooks, each in registration order. After hooks run only if the step succeeded. Hooks add behavior; they never replace versioning, changelog, publication, Git, hosting, or validation.

To remove changelog placeholders or restore categories, use the [changelog contribution template options](../changelog/keep_a_changelog.md#contribution-templates) instead of a hook. To update a README section, use the [Markdown section helper](../markdown.md) in your hook.

## Context

Hooks receive a read-only context:

- `ctx.workflow` is the configured workflow.
- `ctx.release` is the current release. It is `nil` before `capture`.
- `ctx.stage`, `ctx.hook` (`:before` or `:after`), and `ctx.hook_index` (from 1) identify the hook.
- In semantic workflows, `ctx.analysis` and the selected version are available after `validate`.
- `ctx.release.next_version` is set after `prepare_next`.

## Order

Every stage below supports both timings. This is the Actions order; a Rake task run directly runs only its own stages.

1. Setup: `capture`, `validate`, `prepare_release`, `resolve_version`. The `test` command runs next; it is not a hook stage.
2. Checkpoint: `checkpoint`, which wraps `commit_release`, `build_package`, and `tag_release`.
3. Publication: Actions saves artifacts, then runs `authenticate`, `commit_release`, `build_package`, `tag_release`, `publish_registry`, `push_release`, and `publish_hosted_release` (when hosting is enabled).
4. Next development version: `prepare_next`, `commit_next`, `push_next`, `success`.
5. On failure: `failure`, inside the failure-reporting task.

In Actions, `commit_release`, `build_package`, and `tag_release` hooks run twice: in the checkpoint and again in publication. `release:publish` run on its own authenticates and runs them once. `push_release` pushes the release commit and tag; `push_next` pushes only the development commit.

## Safe Edits and Retries

Edit files only in `prepare_release` and `prepare_next` hooks. These hooks run inside `git.stage_changes!`, so their edits go into the release or next-development commit. If a hook raises, later hooks and the stage's after hooks are skipped and the release stops. Changed files are not rolled back.

Use other hooks only to check or observe. Publication rebuilds the package, so edits to built files may be lost. If you replace a workflow operation, keep its publication order and concurrency checks.

Retried tasks and jobs run hooks again, so make them safe to repeat. Some hooks are skipped:

- `authenticate` hooks, when the destination shows the version is already published;
- hosting hooks, when hosting is disabled;
- semantic development hooks, when `bump: false`.

Each Actions step reloads the Rakefile and registers hooks again; nothing is saved between steps.

## Callbacks and Failures

`success:` and `failure:` callbacks run inside their stages, between before and after hooks. To add checks, use `before(:validate)` or `after(:validate)`; the `validate:` option replaces validation entirely.

A hook exception keeps its class and message, and the failure records `failure.error.stage`, `.hook`, and `.hook_index`. Built-in failures have no hook or index. `failure.phase` is the task or Actions step that failed.

For a full example, see the [consumer Rakefile](../../examples/lifecycle_hooks/Rakefile), its [release spec](../../examples/lifecycle_hooks/spec/release_spec.rb), and the [testing helpers](../testing.md).
