# Lifecycle Hooks

Both the [standard](ruby_gem.md) and [semantic](semantic_ruby_gem.md) workflows support ordered `before` and `after` hooks. Register them before `install_tasks`:

```ruby
workflow.before(:validate) { |ctx| validate_project_notes(ctx) }
workflow.after(:prepare_release) { |ctx| update_stable_readme(ctx) }
workflow.after(:prepare_next) { |ctx| update_development_readme(ctx) }

workflow.install_tasks
```

For each stage, before hooks run in registration order, then the built-in operation, then after hooks in registration order if it succeeded. Hooks add behavior; they do not replace versioning, changelog, publication, Git, hosting, or validation.

Use the built-in [changelog contribution template options](../changelog/keep_a_changelog.md#contribution-templates) for placeholder removal and category restoration rather than implementing those operations as hooks.

For README updates, use the [Markdown section helper](../markdown.md) to validate and replace one heading's body while keeping project-specific wording in the hook.

## Context

Hooks receive an immutable execution context with the configured `ctx.workflow` and current `ctx.release`. `ctx.stage`, `ctx.hook`, and `ctx.hook_index` identify the stage, timing, and one-based position. Before capture, `ctx.release` is `nil`; semantic hooks see `ctx.analysis` and the selected version after validation. Next-version hooks see `ctx.release.next_version` after development preparation.

## Order

All stages below support both hook timings. This is the Actions sequence; a direct Rake task runs only its own stages.

- Setup: `capture` → `validate` → `prepare_release` → `resolve_version`. The prepared-release `test` command follows; it is not a hook stage.
- Checkpoint: `checkpoint` wraps `commit_release` → `build_package` → `tag_release`.
- Publication: Actions preserve artifacts, then run `authenticate` → `commit_release` → `build_package` → `tag_release` → `publish_registry` → `push_release` → `publish_hosted_release` (if hosting is enabled).
- Next development: `prepare_next` → `commit_next` → `push_next` → `success`.
- Failure: `failure` runs through the existing failure-reporting task.

Actions run the checkpoint before publication, so `commit_release`, `build_package`, and `tag_release` hooks run twice. Standalone `release:publish` authenticates and runs those three stages once. `push_release` pushes the release commit and tag; `push_next` pushes only the development commit. Artifact preservation and authentication are not part of the checkpoint.

## Safe Edits and Retries

Only `prepare_release` and `prepare_next` are file-editing stages. Both hook timings run inside `git.stage_changes!`, before the release or next-development commit. If a hook raises, later hooks and that stage's after hooks do not run; the release stops, but partial working files are not rolled back.

Use other hooks to validate or observe. Publication rebuilds the package after the Actions checkpoint, so edits to generated artifacts may be replaced. Preserve existing publication ordering and concurrency checks when replacing workflow operations.

Hooks may run again when a task or Actions job is retried; make them idempotent. Authentication hooks are skipped when the destination confirms publication, hosting hooks are skipped when hosting is disabled, and semantic development hooks are skipped when `bump: false`. Each Actions process reloads the Rakefile and registers hooks again; callbacks are not serialized.

## Callbacks and Failures

Existing `success:` and `failure:` callbacks run inside their stages, between before and after hooks. Use `before(:validate)` or `after(:validate)` to add checks; the existing `validate:` option still replaces validation.

Hook exceptions keep their original class and message and are recorded as `failure.error.stage`, `.hook`, and `.hook_index`. Built-in failures have no hook timing or index. `failure.phase` remains the enclosing task or Actions step.

See the [consumer example](../../examples/lifecycle_hooks/Rakefile) for project-local edits using the standard workflow, its [complete release spec](../../examples/lifecycle_hooks/spec/release_spec.rb), and [testing helpers](../testing.md).
