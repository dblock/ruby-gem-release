# `RubyGemRelease::Hosting::GitHubRelease`

Creates a GitHub Release using the installed `gh` command after the gem is published and its commit and tag are pushed.

```ruby
require 'ruby-gem-release/hosting/github_release'

github = RubyGemRelease::Hosting::GitHubRelease.new
github.publish!(release, package: package)
```

## Repository

The optional `repository:` argument identifies the target as `'OWNER/REPO'`. It defaults to `GITHUB_REPOSITORY`; outside Actions, `gh` infers the repository from the checkout.

## Publish

`publish!(release, package: nil, artifacts: [])` creates a release with tag and title `vVERSION`, using the numeric version from the [Release](../release.md) context. It generates release notes and verifies that the tag exists remotely; it never creates a tag automatically. It returns the release URL printed by `gh`.

## Package

`package:` attaches the exact archive returned by [`Package::RubyGem#artifact`](../package/ruby_gem.md#artifact), with its package filename and verified digest, without rebuilding or manual copying.

## Artifacts

Without `package:`, `artifacts:` accepts existing file paths, defaulting to no attachments. Paths containing spaces are supported; line breaks and `#` are rejected because `gh` interprets `#` as an asset label.

## Dry Run

`publish!` validates artifacts but skips `gh` when `release.dry_run?` is true. The publication callback still runs so local builds and tags are exercised.

## Authentication and Errors

Install `gh` and authenticate using `GH_TOKEN` or its existing credentials. The workflow supplies the GitHub Actions token and requires the caller's `contents: write` permission.

Failed commands raise without retries or overwriting existing releases. If package publication and the tag push succeeded, recover only the missing GitHub Release with the preserved artifact; see [RELEASING.md](../../RELEASING.md).

## Workflow Command

The `publish` workflow input defaults to `bundle exec rake release:publish`. Configure that callback to invoke this class after `git.push!`. Set `hosting: nil` in [`Workflow::RubyGem`](../workflow/ruby_gem.md) or omit only `github.publish!` from manual callbacks to disable GitHub Release creation; omitting the whole callback disables package publication too.
