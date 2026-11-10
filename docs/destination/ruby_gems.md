# `RubyGemRelease::Destination::RubyGems`

Extends [`Destination`](../destination.md) for publication to public `rubygems.org`. Package building and verification remain in [`Package::RubyGem`](../package/ruby_gem.md).

## Publish

`published?(release, package:)` reads the built artifact's name and version and compares RubyGems' `sha` with its SHA256 digest. HTTP 404 returns false; an exact match returns true. Missing checksums, different archives, malformed responses, and other HTTP statuses fail.

Readback requests use HTTPS, a 10-second connection timeout, a 30-second read timeout, and no automatic retries. No credentials are needed for readback.

`publish!(release, package:)` skips an exact existing publication or invokes `gem push` only for confirmed absence. It does not rebuild or consult a subsequently edited gemspec.

Configure credentials before calling `publish!` directly. The `release:publish` task calls this destination's `authenticate!(provider:)` first; when prepared-version resolution has selected `rubygems` authentication, it invokes [`RubyGemsCredentials`](../workflow/ruby_gems_credentials.md), with an optional owner-bound exchange for a pending publisher. Without that selection, preconfigured credentials are retained. The helper exports credentials without writing a local credentials file.

## Errors

Changed artifacts, identity mismatches, failed lookups, and upload failures raise without automatic retries. A later workflow reconciles an ambiguously accepted upload; see [recovery instructions](../../RELEASING.md#verify-and-recover).
