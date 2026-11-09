# `RubyGemRelease::Destination`

The base for package registry destinations. A destination owns registry version checks and publication, not package construction, Git pushes, or hosted releases. [`Destination::RubyGems`](destination/ruby_gems.md) is the default and only built-in implementation.

## Contract

Implement `check_version!(name:, version:)` to reject versions that cannot be published, propagating registry lookup failures instead of treating them as absence.

Implement `publish!(release, package:)` to obtain the verified artifact through `package.artifact(release)`, verify its identity, perform the final registry availability check, and publish that exact artifact without rebuilding. Do not retry an ambiguous upload automatically.

The standard workflow checks the configured destination before committing, builds once, tags locally, publishes to the registry, pushes the commit and tag atomically, and then creates the optional hosted release. A destination failure stops before the Git push and hosted release; recovery artifacts remain available.

## Authentication

`authentication` defaults to `nil`, meaning credentials must already be configured for the destination. The built-in RubyGems implementation returns `rubygems` to request the existing Trusted Publishing steps. Other automatic authentication strategies are rejected until implemented.

Both Actions interfaces run RubyGems authentication only when the configured destination requests it. Custom destinations inheriting the default do not perform RubyGems lookups or credential exchanges.

## Configuration

Pass `destination:` to [`Workflow::RubyGem`](workflow/ruby_gem.md). It is available through `ctx.workflow.destination` alongside the configured package and other components.

For manual callbacks, pass the same `package:` and `destination:` objects to `Tasks.install` and use them in your publication callback, as shown in [Detailed Usage](usage.md#custom-callbacks). This also routes prepared-version checks and authentication selection through that destination.

Only one registry destination is selected per workflow. [`Hosting::GitHubRelease`](hosting/github_release.md) remains separate because it creates a hosted release after the tag exists remotely.
