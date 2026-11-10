# `RubyGemRelease::ExecutionProvider`

Separates execution-platform services from release operations. Pass `provider:` to [`Workflow::RubyGem`](workflow/ruby_gem.md), [`Tasks.install`](tasks.md), or [`Workflow::Environment`](workflow/environment.md). The configured workflow exposes its provider through `ctx.workflow.provider`. Execution providers, registry destinations, and hosted-release implementations are independent choices.

`ExecutionProvider.current` selects [`ExecutionProvider::GitHub`](execution_provider/github.md) when `GITHUB_ACTIONS=true`; otherwise it selects the base. Explicit injection overrides detection. No GitLab implementation or pipeline is provided.

## Base Behavior

The base reads release inputs through `fetch(name, *defaults)` from its `environment:` argument, defaulting to `ENV`. `ref` reads a full Git ref from `SOURCE_REF`, and `directory` reads optional `RELEASE_DATA_DIR`. Git identity defaults to `ruby-gem-release` and `ruby-gem-release@localhost`, with `GIT_USER_NAME` and `GIT_USER_EMAIL` overrides.

`export(values)` validates names and single-line string values before updating the current environment. An external execution provider must implement its own transport for subsequent steps. Separate processes must share the exported release values and artifact directory.

`context(**attributes)` creates an immutable provider-neutral execution context; `step_id(task)` uses the logical Rake task ID, and `failed_steps` returns no external history. A provider with execution metadata overrides these methods rather than putting platform I/O in the context.

## Provider Contract

Provider subclasses supply their current ref, temporary directory, environment transport, context construction, step identity, and observed failed step IDs. Environment exports must remain readable through `fetch` in the current process as well as being available to subsequent steps. The pipeline owns setup, concurrency, release authorization, conditional step execution, summaries, and recovery-artifact uploading.

`oidc_token(audience:)` acquires an identity token for the requested audience and raises `NotImplementedError` in the base. `mask(value)` registers a secret with the execution platform; the base logs nothing. The RubyGems exchange uses these operations without implementing platform-specific token acquisition or logging commands. Custom registries may continue using preconfigured credentials.

Switching execution providers does not change hosting automatically. Supply the desired `hosting:` object or `hosting: nil` separately; the standard workflow still defaults to GitHub Releases.
