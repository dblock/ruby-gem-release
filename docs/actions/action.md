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
          rubygems-owner: ${{ inputs.rubygems-owner }}
```

The action checks out the calling repository with full history and sets up Ruby with Bundler caching. It exports and validates inputs, captures the initial version, invokes preparation, resolves the prepared version, validates, authenticates, publishes, preserves recovery artifacts, and prepares the next development iteration. Publication must run from the default branch at its current remote commit. Use a GitHub-hosted Ubuntu runner, matching the reusable workflow's supported execution environment.

## Inputs and Environment

Inputs, command defaults, callback semantics, and exported environment variables match the [workflow reference](release.md#inputs). Set them under the action step's `with:` mapping rather than under a reusable-workflow job. All action inputs are strings. Dispatching the sample workflow publishes the gem.

Inputs are exported through `GITHUB_ENV` for subsequent steps in the job. `release:workflow:configure` rejects line breaks before exporting any values. Override commands execute with release privileges and must be trusted.

## Trusted Publishing

Register a RubyGems trusted publisher for the calling repository, its own workflow filename (`release.yml` above), and environment `release`. Leave the optional Workflow Repository fields blank: the composite action is a step in your workflow, not a reusable workflow from another repository.

For first publication, register a pending trusted publisher and supply its numeric account ID through `rubygems-owner`. Later publications can omit that input. The action uses the same owner-aware helper and credentials action as the reusable workflow, without a stored RubyGems API key.

## Release and Recovery

With the sample, dispatch a first release using `gh workflow run release.yml -f rubygems-owner=YOUR_ACCOUNT_ID`, replacing `YOUR_ACCOUNT_ID` with your numeric account ID. For subsequent releases, omit `rubygems-owner`. Validate locally before authorizing publication.

Recovery artifacts are preserved after the publication callback, even when it fails. Failed callbacks prevent the next development iteration phase. The exact-artifact guarantees and unavoidable publication-before-push recovery window are unchanged; follow [Verify and Recover](../../RELEASING.md#verify-and-recover) rather than blindly retrying a failed release.
