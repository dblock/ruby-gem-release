# `RubyGemRelease::ExecutionProvider`

Connects release tasks to the platform they run on: inputs, exports to later steps, callback contexts, and identity tokens. Pass `provider:` to [`Workflow::RubyGem`](workflow/ruby_gem.md), [`Tasks.install`](tasks.md), or [`Workflow::Environment`](workflow/environment.md); callbacks read it as `ctx.workflow.provider`. Providers, registry destinations, and hosted releases are independent choices.

`ExecutionProvider.current` returns [`ExecutionProvider::GitHub`](execution_provider/github.md) when `GITHUB_ACTIONS=true`, and the base otherwise. An explicit provider wins. No GitLab provider is included.

## Base Behavior

The base reads from its `environment:` argument, default `ENV`:

- `fetch(name, *defaults)` reads a value.
- `ref` reads a full Git ref from `SOURCE_REF`.
- `directory` reads an optional `RELEASE_DATA_DIR`.
- Git identity defaults to `ruby-gem-release` and `ruby-gem-release@localhost`, overridden by `GIT_USER_NAME` and `GIT_USER_EMAIL`.
- `export(values)` checks names and single-line string values, then updates the current environment only.
- `context(**attributes)` creates a frozen base context, `step_id(task)` returns the task name, and `failed_steps` returns `[]`.
- `oidc_token(audience:)` raises `NotImplementedError`, and `mask(value)` does nothing.

## Provider Contract

A subclass supplies its ref, temporary directory, export transport, context, step IDs, and failed step IDs. Exported values must be readable through `fetch` in the current process and reach later steps; separate processes must share them and the artifact directory. Put platform I/O in the provider, not the context.

Implement `oidc_token(audience:)` to get an identity token and `mask(value)` to hide a secret in logs. The RubyGems exchange uses them, so it needs no platform code. Custom registries can keep using preconfigured credentials.

The pipeline still owns setup, concurrency, release approval, conditional steps, summaries, and recovery-artifact uploads.

Changing the provider does not change hosting. Pass `hosting:` or `hosting: nil` yourself; the standard workflow defaults to GitHub Releases.
