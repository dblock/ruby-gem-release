# `RubyGemRelease::GitHubRelease`

Creates a GitHub Release using the installed `gh` command. The workflow invokes this class after publishing the gem and pushing the release commit and tag, before next-version preparation.

```ruby
require 'ruby-gem-release/github_release'

github_release = RubyGemRelease::GitHubRelease.new(repository: 'owner/example')
github_release.publish!(release, artifacts: ['pkg/example-1.0.0.gem'])
```

## Repository

The required `repository:` argument identifies the target as `'OWNER/REPO'`. The class does not infer the repository from the working directory.

## Publish

`publish!(release, artifacts: [])` creates a release with tag and title `vVERSION`, using the numeric version from the [Release](release.md) context. It generates release notes and requires the tag to exist remotely; it never creates a tag automatically. It returns the release URL printed by `gh`.

## Artifacts

`artifacts:` is an array of existing file paths, defaulting to no attachments. The workflow passes a renamed copy of the exact published gem without rebuilding it. Paths containing spaces are supported; paths containing line breaks or `#` are rejected because `gh` interprets `#` as an asset label.

## Authentication and Errors

Install `gh` and authenticate using `GH_TOKEN` or its existing credentials. The workflow supplies the GitHub Actions token and requires the caller's `contents: write` permission.

Failed commands raise an error without retries. Existing releases are not overwritten. If publication and the tag push succeeded but creation failed, verify the remote release first; recover by creating only the missing release and attaching the preserved artifact, not by rerunning publication. See [RELEASING.md](../RELEASING.md).

## Workflow Command

The default `github-release` command is `bundle exec rake release:publish`, registered by [Tasks](tasks.md). Configure `tasks.publish` to invoke this class, or leave the callback unregistered to disable creation. Override the input to customize the command. It receives `GH_TOKEN`, `GITHUB_REPOSITORY`, `GEM_NAME`, `RELEASE_VERSION`, `RELEASE_PREVIOUS_VERSION`, `RELEASE_DATE`, and `RUNNER_TEMP`; the exact gem is at `$RUNNER_TEMP/release.gem`. The entire step is skipped in dry-run mode. Direct class or task calls are not dry-run-aware.
