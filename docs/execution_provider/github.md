# `RubyGemRelease::ExecutionProvider::GitHub`

Implements [`ExecutionProvider`](../execution_provider.md) for GitHub Actions. It reads `GITHUB_REF` and `RUNNER_TEMP`, retains the GitHub bot identity defaults, and supplies [`ExecutionContext::GitHub`](../execution_context/github.md) snapshots and original failed-step outcomes.

Environment exports append to `GITHUB_ENV` and update the current process environment. Names and values are validated before writing files. Capture exports the runner directory as the provider-neutral `RELEASE_DATA_DIR` used by Git and package operations.

`oidc_token(audience:)` requests an identity token through the public Actions OIDC endpoint, replacing any previous audience without discarding other query parameters. It requires HTTPS, bounds request timeouts, disables retries, and rejects malformed responses without including their bodies in errors. The caller must grant `id-token: write`.

`mask(value)` emits the Actions secret-masking command with escaped control characters. [`Workflow::RubyGemsCredentials`](../workflow/ruby_gems_credentials.md) requests the `rubygems.org` audience and performs the separate registry exchange, optionally bound to an owner for first publication.

The reusable workflow and composite action remain Actions-specific orchestration. This adapter does not replace checkout, Ruby setup, environment protection, concurrency, summaries, or artifact-upload steps.
