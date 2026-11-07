# `RubyGemRelease::Workflow`

Supplies the reusable workflow's context checks, invoked through [Tasks](tasks.md). It leaves setup, validation, authentication, artifact uploading, and callback invocation to GitHub Actions.

## Capture

`capture!` checks the dispatch branch, selects the gemspec, reads the initial numeric version, configures checkout-local Git identity, and checks that the default branch has not advanced. It appends `GEMSPEC`, `RELEASE_PREVIOUS_VERSION`, `RELEASE_DATE`, and `RELEASE_INITIAL_COMMIT` to `GITHUB_ENV`. The date is captured in UTC.

## Resolve

`resolve!` reads the prepared gemspec version, validates optional `INPUT_VERSION`, rejects an existing release tag, and appends `RELEASE_VERSION` to `GITHUB_ENV`.

## Environment

Inputs are `INPUT_GEMSPEC`, `INPUT_VERSION`, `GIT_USER_NAME`, `GIT_USER_EMAIL`, `DEFAULT_BRANCH`, `GITHUB_REF`, `GITHUB_ENV`, and `DRY_RUN`. See the [reusable workflow](../.github/workflows/release.yml) for defaults.
