# Isolated Release Workflow

Reference for [`.github/workflows/isolated-release.yml`](../../.github/workflows/isolated-release.yml), an opt-in reusable workflow that keeps publication credentials away from project code. The [standard workflow](release.md) runs everything in one job holding `id-token: write` and `contents: write`, so any gem in the project's development bundle, and any code its tests run, could request a publishing token. The isolated workflow splits the release into two jobs:

- **Build** runs with `contents: read`, outside the `release` environment. It installs the project bundle and runs capture, validation, preparation, resolution, tests, and the checkpoint exactly as the standard workflow does, then seals the release: it prepares and commits the next development iteration locally, running preparation hooks such as README updates, and preserves the gem, its manifest, a Git bundle with the release tag and both commits, and a `publication.json` handoff as the recovery artifact.
- **Publish** runs in the `release` environment with `id-token: write` and `contents: write`. It checks out the caller at the dispatched commit and this library at the reusable workflow's own commit (`job.workflow_sha`), installs no bundle, and publishes with plain Ruby. Project code, including its Gemfile, Rakefile, and gemspec, never runs while publication credentials are available.

## Usage

Add `.github/workflows/release.yml` using the [sample workflow](../../examples/.github/workflows/isolated-release.yml), pinning the reusable workflow by commit SHA:

```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      version:
        description: Optional release version overriding the checked-in version.
        type: string
        required: false

permissions:
  contents: read

jobs:
  release:
    uses: dblock/ruby-gem-release/.github/workflows/isolated-release.yml@v0.8.0
    permissions:
      contents: write
      id-token: write
    with:
      ruby-version: '3.3'
      version: ${{ inputs.version }}
```

Configure the RubyGems trusted publisher as described in [Usage](../../README.md#3-enable-trusted-publishing), with workflow filename `isolated-release.yml`: RubyGems matches the filename of the reusable workflow, not the caller's. A trusted publisher for `isolated-release.yml` cannot be used by the single-job workflow. RubyGems accepts any ref of the workflow repository, so pin the `uses:` line to the full commit SHA of a release tag, with the tag in a trailing comment.

Keep `ruby-gem-release` in your development Gemfile at the same version as the pinned workflow. The build job runs the gem's Rake tasks from your bundle; the publish job runs the library from the workflow commit and rejects a handoff format it does not support.

## Inputs

`version`, `gemspec`, `rubygems-owner`, `git-user-name`, `git-user-email`, `ruby-version`, and `timezone` behave as in the [standard workflow](release.md#inputs). The `validate`, `prepare`, and `test` commands run only in the unprivileged build job. There are no `publish`, `bump`, `success`, `failure`, `prepare-artifacts`, or `artifacts` inputs: publication runs no project commands.

## Requirements

Sealing fails in the build job, before anything is published, unless the workflow uses the default package, RubyGems destination, Git source control, and either the default GitHub Release hosting for the calling repository or `hosting: nil`. Hooks for `authenticate`, `publish_registry`, `push_release`, `publish_hosted_release`, `push_next`, `success`, or `failure`, and `success:` or `failure:` callbacks, are rejected because the publish job cannot run them. Hooks for earlier stages, including `prepare_release`, `prepare_next`, and `commit_next`, run in the build job. [`Workflow::RubyGem`](../workflow/ruby_gem.md) and [`Workflow::SemanticRubyGem`](../workflow/semantic_ruby_gem.md) are supported; semantic releases carry their generated notes and seal no development iteration unless `bump: true`.

The [composite action](action.md) has no isolated mode, because a composite action runs inside one caller-owned job. The `job.workflow_*` contexts the publish job uses are unavailable on GitHub Enterprise Server.

## Publication Order

The publish job verifies the handoff before any push: the run must be on the default branch, the release commit must have the dispatched commit as its only parent, the tag must be a lightweight tag at the release commit, the development commit must have the release commit as its only parent, and the gem must match its manifest checksum and identity. It then:

1. Pushes the release commit to the default branch without the tag. A branch rule that rejects the release token fails here, before the gem is published.
2. Publishes the gem to RubyGems, authenticating through Trusted Publishing only if that exact gem is not already published.
3. Pushes the release tag.
4. Creates or updates the GitHub Release with the gem attached.
5. Pushes the next development commit.

Branch rules must still permit the Actions token to push commits and tags; see [branch permissions](../../RELEASING.md#one-time-setup). If the default branch moves after the build, publication stops with `Default branch advanced; start a new release`.

## Recovery

Every publication step reconciles existing state, so **Re-run failed jobs** on the same workflow run resumes from the first incomplete step, reusing the build job's artifact for its 30-day retention. If the release commit was pushed but the gem was not, the branch contains a release commit without a tag until the rerun completes. See [rerunning releases](../../RELEASING.md#verify-and-recover) before starting a new dispatch after a partial publication.

## Security Notes

Isolation protects the credential, not the build: a compromised dependency in the build job can still alter the gem or the sealed commits it hands off, and publication verifies their structure, not their contents. Required environment reviewers approve the publish job after the build job and its tests have finished, so reviewers can inspect the build log and preserved artifact before approving.
