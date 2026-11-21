# `RubyGemRelease::Destination::RubyGems`

The default [`Destination`](../destination.md): publishes to `rubygems.org`. Building and checking the archive is done by [`Package::RubyGem`](../package/ruby_gem.md).

## Check Version

`published?(release, package:)` looks up the built gem's name and version on RubyGems and compares the registry's `sha` with the archive's SHA256. HTTP 404 returns `false` and a match returns `true`. A missing or different checksum, a malformed response, or any other status raises. Lookups use HTTPS, a 10-second connect timeout, a 30-second read timeout, no retries, and no credentials.

## Publish

`publish!(release, package:)` does nothing if the exact archive is already published; otherwise it runs `gem push`. If the push fails, it succeeds only when a recheck finds the exact archive. It never rebuilds or rereads an edited gemspec.

Set up credentials before calling `publish!` directly. The `release:publish` task first calls `authenticate!(provider:)`. When the workflow selected `rubygems` authentication, this uses [`RubyGemsCredentials`](../workflow/ruby_gems_credentials.md) for Trusted Publishing, optionally bound to an owner for a pending publisher. Credentials go into the environment, not a file. Otherwise, existing credentials are kept.

## Errors

Changed archives, identity mismatches, failed lookups, and failed uploads raise without retries. A later run reconciles an upload that may have been accepted; see [recovery instructions](../../RELEASING.md#verify-and-recover).
