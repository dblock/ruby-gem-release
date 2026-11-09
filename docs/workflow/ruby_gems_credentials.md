# `RubyGemRelease::Workflow::RubyGemsCredentials`

Performs an owner-bound RubyGems Trusted Publishing exchange for a new gem's first publication. It is used only when the reusable workflow receives `rubygems-owner`; without that input, authentication retains the released credentials action.

## Owner

`RubyGemsCredentials.new(owner:, provider:)` requires a positive numeric RubyGems account ID. The execution provider is selected automatically when omitted. Find the ID on your Pending Trusted Publishers page. The ID identifies the account that will own a newly created gem; it is not an API key. A matching, unexpired pending trusted publisher is still required.

## Configure

`configure!` asks the [execution provider](../execution_provider.md) for an OIDC token with audience `rubygems.org` and posts its `jwt` with `owner` to RubyGems' trusted-publisher exchange endpoint. It delegates masking of the OIDC token and returned API key, then exports `RUBYGEMS_API_KEY`, `BUNDLE_GEM__PUSH_KEY`, and `GEM_HOST_API_KEY` through the provider. Only the GitHub provider reads Actions token-request variables or emits Actions logging commands.

The task `release:workflow:credentials` reads `RUBYGEMS_OWNER` through its configured provider. GitHub Actions supplies `ACTIONS_ID_TOKEN_REQUEST_URL`, `ACTIONS_ID_TOKEN_REQUEST_TOKEN`, and `GITHUB_ENV`; the caller must grant `id-token: write`. It writes no stored API-key secret or local credential file. Another provider must supply its own identity-token acquisition and export behavior; this refactor does not add another platform's Trusted Publishing support.

## Errors

Requests use HTTPS and bounded connection/read timeouts, without retries. Invalid IDs, failed requests, malformed JSON, and invalid tokens fail before credentials are exported. Response bodies are not included in errors because they may contain credentials.
