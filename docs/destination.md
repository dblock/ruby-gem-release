# `RubyGemRelease::Destination`

The base for package registry destinations. A destination owns registry authentication, version checks, and publication, not package construction, Git pushes, or hosted releases. [`Destination::RubyGems`](destination/ruby_gems.md) is the default and only built-in implementation.

## Contract

Implement `check_version!(name:, version:)` to reject versions that cannot be published, propagating registry lookup failures instead of treating them as absence.

Implement read-only `published?(release, package:)`: return true only when the registry proves that the exact archive is present, false only for confirmed absence, and raise on mismatches or unverifiable responses. The base raises rather than assuming success.

Implement `publish!(release, package:)` to verify existing publication first, skip an exact match, and upload only a confirmed missing artifact through `package.artifact(release)`. Never rebuild, overwrite, or blindly retry an ambiguous upload.

The standard workflow commits, builds reproducibly, tags locally, verifies or publishes to the registry, pushes commit and tag atomically, and updates the optional hosted release. A destination failure stops before the Git push and hosted release; artifacts remain available for manual inspection.

## Authentication

`release:publish` calls the configured destination's `authenticate!(provider:)` before invoking its publication callback. The base hook does nothing, retaining preconfigured credentials. Override it to authenticate another registry through the supplied execution provider; no YAML authentication step or registry condition is needed.

`authentication` remains the built-in authentication identifier exported as `RELEASE_AUTHENTICATION` during prepared-version resolution. It defaults to `nil`; the RubyGems implementation returns `rubygems` and its hook performs Trusted Publishing when that identifier is selected. Other built-in identifiers are rejected until implemented. Custom destinations can keep `nil` and supply their own hook without RubyGems requests.

Authentication failures stop the publication callback and are captured as publication failures. A missing publication callback invokes no authentication.

## Configuration

Pass `destination:` to [`Workflow::RubyGem`](workflow/ruby_gem.md). It is available through `ctx.workflow.destination` alongside the configured package and other components.

For manual callbacks, pass the same `package:` and `destination:` objects to `Tasks.install` and use them in your publication callback, as shown in [Detailed Usage](usage.md#custom-callbacks). This also routes prepared-version checks and authentication selection through that destination.

Only one registry destination is selected per workflow. [`Hosting::GitHubRelease`](hosting/github_release.md) remains separate because it creates a hosted release after the tag exists remotely.
