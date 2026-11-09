# Composite Release Action

Reference for [`action.yml`](../../action.yml), a step-based alternative to the [reusable workflow](release.md).

## Setup

Install a `ruby-gem-release` gem release compatible with your pinned action release in the calling project's development dependencies and configure its Rakefile as shown in [Usage](../../README.md#1-configure-your-gem). Upgrade them together when adopting breaking changes. The action uses that project's `Gemfile`, callbacks, and shared release tasks; it does not install a separate release configuration.

Save the following as `.github/workflows/release.yml`. Unlike a reusable workflow, an action cannot set its caller's runner, permissions, environment, or concurrency. Keep those job-level settings in the calling workflow:

```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      version:
        description: Optional release version overriding the checked-in version.
        type: string
        required: false
      rubygems-owner:
        description: RubyGems account ID for first publication; omit for an existing gem.
        type: string
        required: false

permissions:
  contents: write
  id-token: write

concurrency:
  group: ruby-gem-release-${{ github.repository }}
  cancel-in-progress: false

jobs:
  release:
    runs-on: ubuntu-latest
    environment: release
    steps:
      - name: Release Gem
        uses: dblock/ruby-gem-release@v0.2.0
        with:
          ruby-version: '3.3'
          version: ${{ inputs.version }}
          rubygems-owner: ${{ inputs.rubygems-owner }}
```

The action checks out the calling repository with full history and sets up Ruby with Bundler caching. It exports and validates inputs, captures the initial version, validates whether to release, invokes preparation, resolves the prepared version, tests, authenticates, publishes, preserves recovery artifacts, and prepares the next development iteration. Publication must run from the default branch at its current remote commit. Use a GitHub-hosted Ubuntu runner, matching the reusable workflow's supported execution environment.

## Inputs and Environment

Inputs, command defaults, callback semantics, and exported environment variables match the [workflow reference](release.md#inputs). Set them under the action step's `with:` mapping rather than under a reusable-workflow job. All action inputs are strings. Dispatching the sample workflow requests publication; configured environment protection rules must pass before the job runs.

Inputs are exported through `GITHUB_ENV` for subsequent steps in the job. `release:workflow:configure` rejects line breaks before exporting any values. Override commands execute with release privileges and must be trusted.

The `validate` command now decides whether to release before preparation; the previous post-preparation `validate` command is renamed to `test`. Empty pending changelog notes skip successfully by default, with no downstream release operations or result callbacks. The action exposes a `skipped` output so caller steps can distinguish that outcome. Custom validation commands must emit one explicit `proceed=true` or `proceed=false` decision to `GITHUB_OUTPUT`. See [Release Validation and Skipping](release.md#release-validation-and-skipping) for the contract and migration.

The optional `version` input selects a release version in standard preparation. The configured version object must implement `set!`; custom preparation commands and callbacks own their file updates and must honor the selection. An empty input releases the checked-in version. See [Release Version](release.md#release-version) for dispatch examples and migration from assertion-only behavior.

The optional `timezone` input defaults to `UTC`; set `timezone: America/New_York` for Eastern Time, including daylight saving changes. This input requires gem and action version `0.3.0` or newer, rather than the older pinned example above. The action validates the identifier and exports `TZ`, affecting subsequent release steps and any later steps in the caller's job. See [Timezone](release.md#timezone) for date capture and service timestamp behavior.

The optional `success` and `failure` command inputs default to `bundle exec rake release:success` and `bundle exec rake release:failure`. Success runs after publication and the next development iteration succeed. Failure runs after a failed phase inside the composite action once Ruby setup has completed and receives a `RubyGemRelease::ReleaseFailure` with a captured Ruby exception when available. It cannot observe or handle failures in caller steps that run outside the action. See [Success and Failure Callbacks](release.md#success-and-failure-callbacks).

## Trusted Publishing

Register a RubyGems trusted publisher for the calling repository, its own workflow filename (`release.yml` above), and environment `release`. Leave the optional Workflow Repository fields blank: the composite action is a step in your workflow, not a reusable workflow from another repository.

For maintainer-only publication, protect the caller job's `release` environment using [Maintainer-Approved Publication](../../RELEASING.md#maintainer-approved-publication). Other repository writers can dispatch, but publication waits for a designated maintainer to approve. Environments do not restrict who can dispatch, and an environment without protection rules does not restrict release access.

For first publication, register a pending trusted publisher and supply its numeric account ID through `rubygems-owner`. Later publications can omit that input. The action uses the same owner-aware helper and credentials action as the reusable workflow, without a stored RubyGems API key.

## Release and Recovery

With the sample, dispatch a first release using `gh workflow run release.yml -f rubygems-owner=YOUR_ACCOUNT_ID`, replacing `YOUR_ACCOUNT_ID` with your numeric account ID. For subsequent releases, omit `rubygems-owner`. Validate locally before authorizing publication.

Recovery artifacts are preserved after the publication callback, even when it fails. Failed callbacks prevent the next development iteration phase. The exact-artifact guarantees and unavoidable publication-before-push recovery window are unchanged; follow [Verify and Recover](../../RELEASING.md#verify-and-recover) rather than blindly retrying a failed release.
