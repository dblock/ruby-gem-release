# `RubyGemRelease::Destination`

The base class for package registries. A destination logs in, checks for an existing version, and uploads. It does not build packages, push to Git, or create hosted releases. [`Destination::RubyGems`](destination/ruby_gems.md) is the default and only built-in one.

## Contract

`published?(release, package:)` must not change anything. Return `true` only when the registry proves the exact archive is there, `false` only when it confirms absence, and raise on mismatches or unverifiable responses. The base raises.

`publish!(release, package:)` must check first, skip an exact match, and upload `package.artifact(release)` only when it is confirmed missing. Never rebuild, overwrite, or blindly retry an upload with an unknown result.

The standard workflow commits, builds, and tags locally; checks or publishes to the registry; pushes the commit and tag together; then updates the optional hosted release. A destination error stops before the push, and the archives stay available for inspection.

## Authentication

`release:publish` calls `authenticate!(provider:)` before the publish callback. The base does nothing, keeping existing credentials. Override it to log in to another registry using the given execution provider; no YAML step is needed.

`authentication` names a built-in login method, exported as `RELEASE_AUTH_MODE` when the prepared version is resolved. The base returns `nil`; `RubyGems` returns `'rubygems'` and then uses Trusted Publishing. Other values raise. A custom destination can return `nil` and log in its own way.

An authentication error stops the publish callback and counts as a publication failure. Without a publish callback, no authentication runs.

## Configuration

Pass `destination:` to [`Workflow::RubyGem`](workflow/ruby_gem.md); callbacks read it as `ctx.workflow.destination`.

For manual callbacks, pass the same `package:` and `destination:` to `Tasks.install` and use them in your publish callback, as in [Detailed Usage](usage.md#custom-callbacks). Version checks and authentication then use that destination.

A workflow has one registry destination. [`Hosting::GitHubRelease`](hosting/github_release.md) is separate because it runs after the tag is pushed.
