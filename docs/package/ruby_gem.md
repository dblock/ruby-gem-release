# `RubyGemRelease::Package::RubyGem`

Owns gem building and RubyGems publication. Commands use argument arrays rather than shell interpolation.

## Gemspec

`RubyGem.new(gemspec: 'example.gemspec')` selects the specification. Without an argument, it uses `GEMSPEC` or the only root gemspec; missing or ambiguous specifications fail. Use the same specification as the workflow, or omit the argument to honor its `gemspec` input. `gemspec` returns the selected absolute path.

## Directory

The optional `directory:` defaults to `RUNNER_TEMP`, or a new temporary directory outside Actions. `directory` returns this location. Keep it outside the working tree so build artifacts do not enter release commits.

## Version

`version` reads the gemspec version in a fresh Ruby process so callback edits are visible even if the specification was previously loaded.

## Check Version

`check_version!('1.2.3')` checks the selected gem's name and the specified version using the public RubyGems version API. HTTP 200 rejects an already published version with recovery guidance; only HTTP 404 permits proceeding. Redirects, other response statuses, and connection failures stop the release rather than assuming the version is available. Requests use HTTPS, a 10-second connection timeout, a 30-second read timeout, and no automatic retries. No credentials are needed.

Both Actions interfaces check the prepared version during resolution, before validation and authentication. The standard publication callback checks again before committing, building, or tagging. Custom callbacks should call `package.check_version!(release.version)` before their release commit; call it earlier with the version you intend to prepare if you also want to avoid changing preparation files on a known duplicate.

This checks RubyGems, not local tags or installed gems, and permits unpublished maintenance versions even when newer versions exist. It is not a version reservation: another publisher can win the race between checking and uploading, and RubyGems remains the final authority. The check is for public `rubygems.org`, not private registries.

## Build

`build!(release)` builds `release.gem` once, checks its version, and records its name, version, and checksum in `release.json`. It returns the package filename. Call it after the release commit and before tagging; `Git#tag!` rejects build mutations in the checkout.

## Artifact

`artifact(release)` verifies the preserved version and digest and returns a copy named `NAME-VERSION.gem`. Both publishers use that exact archive without rebuilding. A new instance using the same directory can reopen it for recovery.

## Publish

`publish!(release)` verifies the artifact, checks its exact built name and version against RubyGems once more, and invokes `gem push` only if the version is absent. This final check also applies to standalone package callers that did not use the earlier version check. Configure RubyGems credentials beforehand; the workflow uses Trusted Publishing.

## Errors

Build failures, version mismatches, changed artifacts, published versions, failed version checks, and failed uploads raise without automatic retries. Before retrying an ambiguous upload, check RubyGems; see [recovery instructions](../../RELEASING.md#verify-and-recover).
