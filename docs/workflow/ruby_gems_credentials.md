# `RubyGemRelease::Workflow::RubyGemsCredentials`

`RubyGemsCredentials` uses RubyGems Trusted Publishing to trade the CI job's identity token for a short-lived API key, so you never store one. It works for existing gems and a new gem's first release. The RubyGems destination calls it during `release:publish`, so the YAML interfaces need no authentication step.

## Owner

`RubyGemsCredentials.new(owner: nil, provider: ExecutionProvider.current)` takes an optional RubyGems account ID.

- For an existing gem, omit `owner` (or pass `nil` or an empty string).
- For a first release, pass the numeric ID from your RubyGems Pending Trusted Publishers page. It names the account that will own the gem; it is not an API key. A matching, unexpired pending trusted publisher is still required.

Any other value must be a positive number; spaces are rejected, not treated as empty.

## Configure

`configure!`:

1. Asks the [execution provider](../execution_provider.md) for an OIDC token with audience `rubygems.org`.
2. Posts `{jwt: token}`, plus `owner` if set, to the RubyGems trusted-publisher exchange endpoint.
3. Masks the token and the returned API key in logs.
4. Exports the key as `RUBYGEMS_API_KEY`, `BUNDLE_GEM__PUSH_KEY`, and `GEM_HOST_API_KEY`.

On GitHub Actions, the caller must grant `id-token: write`; Actions supplies `ACTIONS_ID_TOKEN_REQUEST_URL`, `ACTIONS_ID_TOKEN_REQUEST_TOKEN`, and `GITHUB_ENV`. Other providers must fetch their own identity token and export values; this class adds no Trusted Publishing support for other platforms.

The `release:workflow:credentials` task runs `configure!` for custom commands, reading optional `RUBYGEMS_OWNER_ID`.

## Check

`check!` tests your Trusted Publishing setup without exporting anything. It runs the same exchange as `configure!`, masks both credentials, and returns:

- the token's `repository`, `job_workflow_ref`, and `environment` claims;
- the key's `scopes`, `expires_at`, and `owner`, when present.

It raises unless the key grants `push_rubygem`. The key is discarded; it expires after 15 minutes. RubyGems does not report which gems a publisher covers, so a passing check does not prove it is attached to your gem.

If RubyGems rejects the exchange, the error lists the token's `repository`, `job_workflow_ref`, and `environment` claims, but not the token or response body. If the claims cannot be decoded, the error is generic.

## Custom Publication Commands

This class only sets environment variables. Unlike the `rubygems/configure-rubygems-credentials` action it replaces, it never creates or changes `~/.gem/credentials`.

Ruby publication callbacks run by `release:publish` see the exported variables. A custom publication command must inherit them and use `GEM_HOST_API_KEY`, `RUBYGEMS_API_KEY`, or `BUNDLE_GEM__PUSH_KEY`, whichever its tool reads; the standard `gem push` uses `GEM_HOST_API_KEY`. Do not assume a credentials file or named keys exist. Never log the key or save it in release artifacts.

A `publish` command override that skips `release:publish` also skips authentication, so run `release:workflow:credentials` first. Better, keep the default task and register a Ruby publication callback, so the destination authenticates for you.

This class supports only the RubyGems Trusted Publishing exchange. It does not take API tokens, assume roles, or support other gem servers.

## Errors

Requests use HTTPS with timeouts and no retries. Invalid IDs, failed requests, malformed JSON, and invalid tokens fail before anything is exported. Errors never include response bodies, because they may contain credentials.
