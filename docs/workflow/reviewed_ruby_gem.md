# Reviewed Ruby Gem Workflow

Use `Workflow::ReviewedRubyGem` when release preparation is already merged and a trusted signed tag already exists remotely. It runs the normal validation, testing, artifact preservation, publication, and notification tasks without editing release files, making commits, creating tags, pushing Git refs, or preparing a development version.

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

`branches:` is a required, nonempty list of exact Git branch names, not patterns. The provider ref must name an allowed branch, the checkout must be clean and at its current remote tip, and the package version must match the selected release version. The default manual and semantic workflows retain their default-branch policy.

Before building and publishing, the workflow requires `vVERSION` at the captured checkout commit, the exact same tag object on the remote, and successful `git verify-tag`. Configure trusted GPG or SSH signers on the runner before invoking release tasks. Lightweight, unsigned, missing, conflicting, or untrusted tags fail rather than being created or replaced. Checkout and branch advancement fail even when the old source remains an ancestor. The default `SourceControl::ReviewedGit` wraps a `SourceControl::Git` checkout and exposes no operations that stage, commit, tag, or push.

The workflow does not infer review approval from a signature. Keep project-specific merged-PR, maintainer, codename, backport, and release-note policies in `validate:` or lifecycle hooks. Protect the release environment and allowed deployment branches. No option bypasses signature verification.

`release:prepare` only verifies source; `release:bump` is a no-op. The workflow is independent of `Workflow::RubyGem` and accepts no `version:` or `changelog:`; it shares only lifecycle hooks and task installation. Build hooks must not edit tracked files or leave untracked files. A verified Git bundle is retained for inspection. `notes:` optionally accepts a [read-only notes reader](../changelog/notes.md); invalid notes fail validation before registry publication. Custom notifications continue to receive normal execution contexts.

## Package Sets and Retained Inputs

Pass a [package collection](../package/collection.md) as `package:` to publish ruby and Java archives together. Built packages need separate directories. Prebuilt packages need explicit paths, reviewed SHA256 digests, and expected identities; they verify instead of rebuilding. Use [content auditing](../package/ruby_gem.md#content-audit) to bind archive members to Git source, with explicit exceptions for generated outputs.

Both Actions interfaces accept `prepare-artifacts`, an optional trusted command after dependency setup and before context capture, and `artifacts`, additional newline-separated paths to preserve before publication. Their defaults are empty and leave the existing workflow unchanged. For example, with an explicitly approved build run:

```yaml
with:
  ruby-version: '4.0'
  prepare-artifacts: gh run download 123456 --name verified-gems --dir "$RUNNER_TEMP/reviewed"
  artifacts: |
    ${{ runner.temp }}/reviewed/*.gem
    ${{ runner.temp }}/reviewed/*.json
```

Replace the sample run ID and artifact name with reviewed inputs; do not discover the most recent successful build during publication. Downloading Actions artifacts requires the caller's `actions: read` permission. Prepare inputs outside the checkout so capture stays clean. A Rakefile using prebuilt packages is loaded after this preparation command; its configured digests and audit policy remain authoritative.

The default `release.gem`, `release.json`, and `release.bundle` paths remain included in artifact preservation alongside additional paths. A collection may only produce member archives and the bundle, so explicitly list every member and its reviewed manifest. Uploads are a workflow transport boundary, not a substitute for Ruby-side verification; local consumer tests do not validate live Actions artifact transfer or OIDC.
