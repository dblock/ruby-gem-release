# `RubyGemRelease::Destination::RubyGems`

Extends [`Destination`](../destination.md) for publication to public `rubygems.org`. Package building and verification remain in [`Package::RubyGem`](../package/ruby_gem.md).

## Check Version

`check_version!(name: package.name, version: release.version)` checks the specified name and version through the public RubyGems API. HTTP 200 rejects an already published version with recovery guidance; only HTTP 404 permits proceeding. Redirects, other statuses, and connection failures stop the release instead of assuming availability.

Requests use HTTPS, a 10-second connection timeout, a 30-second read timeout, and no automatic retries. No credentials are needed. This is not a reservation: another publisher can win the race before uploading, and RubyGems remains authoritative.

Both Actions interfaces use the configured destination when resolving the prepared version, before testing and authentication. The standard publication callback checks again before committing, building, or tagging.

## Publish

`publish!(release, package:)` obtains the verified artifact, reads its actual built name and version, rejects a version mismatch, checks registry availability again, and invokes `gem push` with that exact filename. It does not rebuild or consult a subsequently edited gemspec.

Configure credentials before calling `publish!` directly. The `release:publish` task calls this destination's `authenticate!(provider:)` first; when prepared-version resolution has selected `rubygems` authentication, it invokes [`RubyGemsCredentials`](../workflow/ruby_gems_credentials.md), with an optional owner-bound exchange for a pending publisher. Without that selection, preconfigured credentials are retained. The helper exports credentials without writing a local credentials file.

## Errors

Changed artifacts, identity mismatches, published versions, failed lookups, and upload failures raise without automatic retries. Before retrying an ambiguous upload, check RubyGems; see [recovery instructions](../../RELEASING.md#verify-and-recover).
