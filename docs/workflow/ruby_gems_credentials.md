# `RubyGemRelease::Workflow::RubyGemsCredentials`

Performs an owner-bound RubyGems Trusted Publishing exchange for a new gem's first publication. It is used only when the reusable workflow receives `rubygems-owner`; without that input, authentication retains the released credentials action.

## Owner

`RubyGemsCredentials.new(owner:)` requires a positive numeric RubyGems account ID. Find it on your Pending Trusted Publishers page. The ID identifies the account that will own a newly created gem; it is not an API key. A matching, unexpired pending trusted publisher is still required.

## Configure

`configure!` requests the GitHub Actions OIDC token with audience `rubygems.org` and posts its `jwt` with `owner` to RubyGems' trusted-publisher exchange endpoint. It masks the OIDC token and returned API key before exporting `RUBYGEMS_API_KEY`, `BUNDLE_GEM__PUSH_KEY`, and `GEM_HOST_API_KEY` through `GITHUB_ENV`.

The task `release:workflow:credentials` reads `RUBYGEMS_OWNER`. GitHub Actions supplies `ACTIONS_ID_TOKEN_REQUEST_URL`, `ACTIONS_ID_TOKEN_REQUEST_TOKEN`, and `GITHUB_ENV`; the caller must grant `id-token: write`. It writes no stored API-key secret or local credential file.

## Errors and Dry Runs

Requests use HTTPS and bounded connection/read timeouts, without retries. Invalid IDs, failed requests, malformed JSON, and invalid tokens fail before credentials are exported. Response bodies are not included in errors because they may contain credentials. The workflow skips this task in dry runs; calling it directly requests credentials and is not a dry-run operation.
