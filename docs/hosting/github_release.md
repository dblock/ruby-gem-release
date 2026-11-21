# `RubyGemRelease::Hosting::GitHubRelease`

Creates a GitHub Release with the `gh` command, after the gem is published and the commit and tag are pushed.

```ruby
require 'ruby-gem-release/hosting/github_release'

github = RubyGemRelease::Hosting::GitHubRelease.new
github.publish!(release, package: package)
```

## Repository

`repository:` is the target as `'OWNER/REPO'`. It defaults to `GITHUB_REPOSITORY`; outside Actions, `gh` uses the current checkout.

## Publish

`latest:` sets whether the release is marked latest when created or updated: `true`, `false`, or `nil` (default) to let GitHub decide and leave existing releases alone. Use `latest: false` on maintenance branches so an older release is never promoted, even briefly. Existing releases are compared with GitHub's current latest first.

`publish!(release, package: nil, artifacts: [])` creates a release with tag and title `vVERSION` from the [Release](../release.md) version. The tag must already exist on GitHub; it is never created here. With `release.notes`, the nonempty notes are passed in a private temporary `--notes-file` that is then deleted; otherwise GitHub generates notes. The standard workflow passes the released changelog section when it can read it. It returns the release URL printed by `gh`.

## Package

Reruns are safe. For an existing release, `publish!` checks metadata and assets, updates a differing title, latest status, or explicit notes, and uploads missing or changed assets with `--clobber`. Matching output is left alone, and generated notes are kept when none were passed. Assets without a server digest are downloaded and hashed. Invalid responses and duplicate asset names raise.

`package:` attaches the exact archives from [`Package::RubyGem#artifact`](../package/ruby_gem.md#artifact), with their filenames and checked digests, without rebuilding.

## Artifacts

Without `package:`, `artifacts:` takes existing file paths and defaults to none. Spaces are fine; line breaks and `#` raise, because `gh` reads `#` as an asset label.

## Authentication and Errors

Install `gh` and log in with `GH_TOKEN` or existing credentials. The workflow passes the Actions token, which needs `contents: write`.

Failed commands raise without retries. A rerun checks what exists and fixes missing or changed details and assets; see [Verify and Recover](../../RELEASING.md#verify-and-recover).

## Workflow Command

The `publish` workflow input defaults to `bundle exec rake release:publish`; call this class from it after `git.push!`. To skip GitHub Releases, set `hosting: nil` in [`Workflow::RubyGem`](../workflow/ruby_gem.md) or remove only `github.publish!` from manual callbacks. Removing the whole callback also stops gem publishing.
