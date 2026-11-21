# `RubyGemRelease::ExecutionProvider::GitHub`

The [`ExecutionProvider`](../execution_provider.md) for GitHub Actions. It reads `GITHUB_REF` and `RUNNER_TEMP`, defaults the Git identity to the GitHub bot, and creates [`ExecutionContext::GitHub`](../execution_context/github.md) contexts with step results and failed-step outcomes.

`export(values)` validates names and values, appends them to `GITHUB_ENV` for later steps, and sets them in the current process. Capture exports the runner directory as `RELEASE_DATA_DIR` for Git and package operations.

`oidc_token(audience:)` requests an OpenID Connect identity token from the Actions token endpoint, replacing any audience in the URL but keeping other parameters. It requires HTTPS, bounds timeouts, does not retry, and raises on malformed responses without including the body. The workflow must grant `id-token: write`.

`mask(value)` hides a secret in Actions logs, escaping control characters. [`Workflow::RubyGemsCredentials`](../workflow/ruby_gems_credentials.md) uses both to get a `rubygems.org` token and exchange it for credentials, optionally bound to an owner for a first release.

The reusable workflow and composite action still handle checkout, Ruby setup, environment protection, concurrency, summaries, and artifact uploads.
