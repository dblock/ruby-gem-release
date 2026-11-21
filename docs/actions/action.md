# Composite Release Action

Reference for [`action.yml`](../../action.yml), a step you add to your own job instead of calling the [reusable workflow](release.md).

## Setup

Add a `ruby-gem-release` version that matches your pinned action version to your development dependencies, and configure the Rakefile as in [Usage](../../README.md#1-configure-your-gem). Upgrade both together. The action uses your `Gemfile`, callbacks, and release tasks.

Save this as `.github/workflows/release.yml`. An action can't set the runner, permissions, environment, or concurrency, so your workflow sets them:

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
        uses: dblock/ruby-gem-release@v0.9.0
        with:
          ruby-version: '3.3'
          version: ${{ inputs.version }}
          rubygems-owner: ${{ inputs.rubygems-owner }}
```

The action checks out your repository with full history, sets up Ruby with Bundler caching, and runs the same steps as the [reusable workflow](release.md#execution): validate, prepare, test, checkpoint and preserve artifacts, publish, and bump. Each run uses only the current checkout and inputs, so commands must be safe to rerun. Conflicting tags and unrelated branch changes fail before publication. Use a GitHub-hosted Ubuntu runner, as the reusable workflow does.

## Inputs and Environment

Inputs, defaults, callbacks, and environment variables match the [workflow reference](release.md#inputs), with these differences:

- Set inputs under the step's `with:`, not the job's.
- All inputs are strings, and there is no `dry-run` input.
- `gemfile` defaults to empty, which keeps any `BUNDLE_GEMFILE` your job already sets. A value is exported for all later steps before Ruby setup.
- Inputs are exported through `GITHUB_ENV`, so they stay set for later steps in your job. `release:workflow:configure` rejects line breaks before exporting anything.
- `timezone` exports `TZ`, which also affects your later steps. See [Timezone](release.md#timezone).
- `failure` only sees failures inside the action, not in your own steps. See [Success and Failure Callbacks](release.md#success-and-failure-callbacks).

Dispatching the sample workflow starts a real release once environment protection rules pass. Command overrides run with release credentials and must be trusted. For `validate` and `version`, see [Release Validation](release.md#release-validation) and [Release Version](release.md#release-version).

For [already-reviewed source and package collections](../workflow/reviewed_ruby_gem.md), configure `Workflow::ReviewedRubyGem` in the Rakefile. `prepare-artifacts` runs after Ruby setup, before the release tasks load, to prepare explicit input archives. `artifacts` adds paths to preserve, one per line. Both default to empty and must use reviewed inputs.

## Trusted Publishing

Register a RubyGems trusted publisher with your repository, your workflow filename (`release.yml` above), and environment `release`. Leave the Workflow Repository fields blank: the action is a step in your workflow, not a reusable workflow from another repository.

For first publication, pass the numeric account ID from the pending trusted publisher as `rubygems-owner`; omit it later. `release:publish` logs in with the [credentials helper](../workflow/ruby_gems_credentials.md) without a stored API key or `~/.gem/credentials`. A `publish` override that skips that task must log in itself.

To require approval from a maintainer, protect the `release` environment with [Maintainer-Approved Publication](../../RELEASING.md#maintainer-approved-publication). Other writers can still dispatch, but publication waits for approval. Environments can't limit who dispatches, and one without protection rules restricts nothing.

The action runs the [release prerequisites](release.md#release-prerequisites) check before any edit or publication. To check without releasing, run `bundle exec rake release:workflow:preflight` in a job in the same workflow file and `release` environment, with `id-token: write`. RubyGems matches the workflow file and environment, so a check from elsewhere proves nothing about the release job.

## Release and Recovery

Dispatch the first release with `gh workflow run release.yml -f rubygems-owner=YOUR_ACCOUNT_ID`, using your numeric account ID. For later releases, omit `rubygems-owner`. Validate locally before you approve publication.

Do not merge into the default branch while a release runs; see [recovery](release.md#default-branch-advanced-during-publication). Reruns never restore an earlier run or pick up unfinished releases. See [Verify and Recover](../../RELEASING.md#verify-and-recover).
