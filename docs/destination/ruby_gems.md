# `RubyGemRelease::Destination::RubyGems`

Extends [`Destination`](../destination.md) for publication to public `rubygems.org`. Package building and verification remain in [`Package::RubyGem`](../package/ruby_gem.md).

## Check Version

`check_version!(name: package.name, version: release.version)` checks the specified name and version through the public RubyGems API. HTTP 200 rejects an already published version with recovery guidance; only HTTP 404 permits proceeding. Redirects, other statuses, and connection failures stop the release instead of assuming availability.

Requests use HTTPS, a 10-second connection timeout, a 30-second read timeout, and no automatic retries. No credentials are needed. This is not a reservation: another publisher can win the race before uploading, and RubyGems remains authoritative.

Both Actions interfaces use the configured destination when resolving the prepared version, before testing and authentication. The standard publication callback checks again before committing, building, or tagging.

## Publish

`publish!(release, package:)` obtains the verified artifact, reads its actual built name and version, rejects a version mismatch, checks registry availability again, and invokes `gem push` with that exact filename. It does not rebuild or consult a subsequently edited gemspec.

Configure credentials before calling it directly. In Actions, this destination requests `rubygems` authentication, retaining both existing Trusted Publishing paths: the pinned credentials action or owner-bound exchange for a pending publisher.

## Errors

Changed artifacts, identity mismatches, published versions, failed lookups, and upload failures raise without automatic retries. Before retrying an ambiguous upload, check RubyGems; see [recovery instructions](../../RELEASING.md#verify-and-recover).
