# `RubyGemRelease::Workflow::RubyGemsCredentials`

Performs RubyGems Trusted Publishing exchanges for both existing gems and a new gem's first publication. The RubyGems destination invokes this helper as part of `release:publish` when automatic RubyGems authentication is selected. Neither YAML interface contains a registry-specific authentication step.

## Owner

`RubyGemsCredentials.new(owner: nil, provider: ExecutionProvider.current)` accepts an optional positive numeric RubyGems account ID. An omitted, `nil`, or empty owner selects the existing-gem exchange without an owner field. A nonempty owner must be a positive numeric ID; spaces are not treated as an empty value.

For first publication, find the ID on your Pending Trusted Publishers page. The ID identifies the account that will own a newly created gem; it is not an API key. A matching, unexpired pending trusted publisher is still required.

## Configure

`configure!` asks the [execution provider](../execution_provider.md) for an OIDC token with audience `rubygems.org` and posts `{jwt: token}` to RubyGems' trusted-publisher exchange endpoint, adding `owner` only when supplied. It delegates masking of the OIDC token and returned API key, then exports `RUBYGEMS_API_KEY`, `BUNDLE_GEM__PUSH_KEY`, and `GEM_HOST_API_KEY` through the provider. Only the GitHub provider reads Actions token-request variables or emits Actions logging commands.

The direct task `release:workflow:credentials` remains available for custom commands and reads optional `RUBYGEMS_OWNER` through its configured provider. GitHub Actions supplies `ACTIONS_ID_TOKEN_REQUEST_URL`, `ACTIONS_ID_TOKEN_REQUEST_TOKEN`, and `GITHUB_ENV`; the caller must grant `id-token: write`. Another provider must supply its own identity-token acquisition and export behavior; this does not add another platform's Trusted Publishing support.

## Custom Publication Commands

Authentication is environment-only: the helper neither creates nor modifies `~/.gem/credentials`. This differs from the replaced `rubygems/configure-rubygems-credentials` action, which also wrote that file. Existing credential files are left untouched.

Ruby publication callbacks invoked by `release:publish` receive the authenticated environment. Custom publication commands must inherit the exported environment and use `GEM_HOST_API_KEY`, `RUBYGEMS_API_KEY`, or `BUNDLE_GEM__PUSH_KEY` as appropriate for their tool. Do not assume a credentials file exists or rely on named keys in that file. The standard `gem push` publication uses `GEM_HOST_API_KEY`. Credentials are short-lived and must not be logged or persisted in release artifacts.

A `publish` command override that bypasses `release:publish` also bypasses destination authentication and must perform it explicitly. For RubyGems, it can invoke `release:workflow:credentials` before its own publication command. Prefer registering a custom Ruby publication callback and retaining the default task so the configured destination handles authentication automatically.

This helper supports only the RubyGems Trusted Publishing exchange, not API-token inputs, role assumption, or alternate gem servers.

## Errors

Requests use HTTPS and bounded connection/read timeouts, without retries. Invalid IDs, failed requests, malformed JSON, and invalid tokens fail before credentials are exported. Response bodies are not included in errors because they may contain credentials.
