# `RubyGemRelease::Workflow::Context`

Supplies context checks for the reusable workflow and composite action, invoked through [Tasks](../tasks.md). It leaves setup, validation, authentication, artifact uploading, and callback invocation to GitHub Actions. For inputs and defaults, see the [GitHub Actions workflow reference](../actions/release.md).

## Configure

`configure!` exports the composite action's input environment, including `TZ`, for subsequent steps through `GITHUB_ENV`. It validates the timezone and rejects line breaks in all values before writing any of them. The reusable workflow supplies the same values through its job environment and does not need this method.

## Capture

`capture!` checks the dispatch branch, validates the timezone, configures checkout-local Git identity, rejects a dirty checkout after dependency installation, selects the gemspec, reads the initial numeric version, and checks that the default branch has not advanced. It appends `TZ`, `GEMSPEC`, `RELEASE_PREVIOUS_VERSION`, `RELEASE_DATE`, and `RELEASE_INITIAL_COMMIT` to `GITHUB_ENV`. The date is captured once in `TZ`, defaulting to UTC when that variable is absent. Invalid identifiers fail before Git configuration or environment export.

## Resolve

`resolve!` reads the prepared gemspec version, validates optional `INPUT_VERSION`, rejects an existing release tag, stages the trusted preparation command's changes and saves the index tree before validation, and appends `RELEASE_VERSION` to `GITHUB_ENV`. Later working tree or index changes are rejected by publication rather than staged automatically.

## Environment

Inputs are `INPUT_GEMSPEC`, `INPUT_VERSION`, `GIT_USER_NAME`, `GIT_USER_EMAIL`, `DEFAULT_BRANCH`, `GITHUB_REF`, `GITHUB_ENV`, and optional `TZ`. Timezone identifiers must resolve under `/usr/share/zoneinfo`, as on the supported Ubuntu runners. Configuration also exports `RUBYGEMS_OWNER` for authentication. See the [reusable workflow](../../.github/workflows/release.yml) and [composite action](../../action.yml) for defaults.
