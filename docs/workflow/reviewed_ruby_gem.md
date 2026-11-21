# Reviewed Ruby Gem Workflow

Use `Workflow::ReviewedRubyGem` when the release changes are already merged and a trusted signed tag already exists on the remote. It validates, tests, saves artifacts, publishes, and notifies, but never edits files, commits, tags, pushes, or bumps the version.

```ruby
require 'ruby-gem-release/workflow/reviewed_ruby_gem'
require 'ruby-gem-release/changelog/notes'

provider = RubyGemRelease::ExecutionProvider.current
package = RubyGemRelease::Package::RubyGem.new(directory: provider.directory)
RubyGemRelease::Workflow::ReviewedRubyGem.new(
  package: package,
  branches: ['master', '7-2-stable'],
  notes: RubyGemRelease::Changelog::Notes.new,
  hosting: RubyGemRelease::Hosting::GitHubRelease.new(latest: false),
  provider: provider
).install_tasks
```

## Source Guards

Required `branches:` lists exact branch names, not patterns. The release fails unless:

- the current ref is one of those branches;
- the checkout is clean and exactly at the remote branch tip;
- the package version matches the release version.

Before building and publishing, it also requires that:

1. Tag `vVERSION` points at the checkout commit.
2. The remote has the exact same tag object.
3. `git verify-tag` succeeds.

Configure trusted GPG or SSH signers on the runner first. Lightweight, unsigned, missing, conflicting, or untrusted tags fail; they are never created or replaced, and no option skips signature verification. The default `SourceControl::ReviewedGit` has no methods that stage, commit, tag, or push.

A valid signature does not prove review. Put merged-PR, maintainer, backport, or release-note policies in `validate:` or lifecycle hooks. Protect the release environment and limit its deployment branches.

## Differences from the Standard Workflow

`release:prepare` only verifies the source, and `release:bump` does nothing. The workflow accepts no `version:` or `changelog:` and shares only hooks and task installation with `Workflow::RubyGem`. Build hooks must leave the checkout clean. A verified Git bundle is kept for inspection.

`notes:` optionally takes a [read-only notes reader](../changelog/notes.md). Invalid or empty notes fail validation, before anything is published.

## Package Sets and Retained Inputs

To publish Ruby and Java archives together, pass a [package collection](../package/collection.md) as `package:`. Packages built during the release need separate directories. Prebuilt packages need explicit paths, reviewed SHA256 digests, and expected identities; they are verified, not rebuilt. [Content auditing](../package/ruby_gem.md#content-audit) checks archive contents against Git source, with listed exceptions for generated files.

Both Actions interfaces accept two optional inputs, both empty by default:

- `prepare-artifacts`: a trusted command that runs after dependency setup and before capture.
- `artifacts`: extra newline-separated paths to save before publication.

For example, to use the output of an approved build run:

```yaml
with:
  ruby-version: '4.0'
  prepare-artifacts: gh run download 123456 --name verified-gems --dir "$RUNNER_TEMP/reviewed"
  artifacts: |
    ${{ runner.temp }}/reviewed/*.gem
    ${{ runner.temp }}/reviewed/*.json
```

Use a run ID and artifact name you reviewed; do not pick the latest successful build during publication. Downloading artifacts needs `actions: read` permission in the caller. Download outside the checkout so it stays clean. The Rakefile loads after this command, and its digests and audit policy still decide what is accepted.

`release.gem`, `release.json`, and `release.bundle` are always saved too. A collection may produce only member archives and the bundle, so list every member archive and its reviewed manifest in `artifacts`. Uploads do not replace Ruby-side verification. Local tests do not cover live Actions artifact transfer or OIDC.
