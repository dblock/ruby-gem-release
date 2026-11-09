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

`publish!(release, package: nil, artifacts: [])` creates a release with tag and title `vVERSION`, using the numeric version from the [Release](../release.md) context. It verifies that the tag exists remotely and never creates a tag automatically. With `release.notes`, it supplies that nonempty body through a private temporary `--notes-file` and removes the file afterward; otherwise it retains GitHub's `--generate-notes`. It returns the release URL printed by `gh`.

## Package

`published?(release, package:)` verifies existing metadata and every expected asset. `publish!` updates differing titles, release status, and explicit notes, and uploads missing or changed assets with `--clobber`; matching outputs are no-ops. Unspecified platform-generated notes are retained. Assets without a server digest are downloaded and hashed. Invalid responses and duplicate asset names fail rather than being guessed.

`package:` attaches the exact archive returned by [`Package::RubyGem#artifact`](../package/ruby_gem.md#artifact), with its package filename and verified digest, without rebuilding or manual copying.

## Artifacts

Without `package:`, `artifacts:` accepts existing file paths, defaulting to no attachments. Paths containing spaces are supported; line breaks and `#` are rejected because `gh` interprets `#` as an asset label.

## Authentication and Errors

Install `gh` and authenticate using `GH_TOKEN` or its existing credentials. The workflow supplies the GitHub Actions token and requires the caller's `contents: write` permission.

Failed commands raise without retries or overwriting existing releases. If package publication and the tag push succeeded, recover only the missing GitHub Release with the preserved artifact; see [RELEASING.md](../../RELEASING.md).

## Workflow Command

The `publish` workflow input defaults to `bundle exec rake release:publish`. Configure that callback to invoke this class after `git.push!`. Set `hosting: nil` in [`Workflow::RubyGem`](../workflow/ruby_gem.md) or omit only `github.publish!` from manual callbacks to disable GitHub Release creation; omitting the whole callback disables package publication too.
