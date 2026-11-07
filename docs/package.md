# `RubyGemRelease::Package`

Owns gem building and RubyGems publication. Commands use argument arrays rather than shell interpolation.

## Gemspec

`Package.new(gemspec: 'example.gemspec')` selects the specification. Without an argument, it uses `GEMSPEC` or the only root gemspec; missing or ambiguous specifications fail. Use the same specification as the workflow, or omit the argument to honor its `gemspec` input. `gemspec` returns the selected absolute path.

## Directory

The optional `directory:` defaults to `RUNNER_TEMP`, or a new temporary directory outside Actions. `directory` returns this location. Keep it outside the working tree so build artifacts do not enter release commits.

## Version

`version` reads the gemspec version in a fresh Ruby process so callback edits are visible even if the specification was previously loaded.

## Build

`build!(release)` builds `release.gem` once, checks its version, and records its name, version, and checksum in `release.json`. It returns the package filename. Call it after the release commit and before tagging; `Git#tag!` rejects build mutations in the checkout.

## Artifact

`artifact(release)` verifies the preserved version and digest and returns a copy named `NAME-VERSION.gem`. Both publishers use that exact archive without rebuilding. A new instance using the same directory can reopen it for recovery.

## Publish

`publish!(release)` verifies the artifact and invokes `gem push`. It skips uploading when `release.dry_run?` is true, while still verifying the artifact. Configure RubyGems credentials beforehand; the workflow uses Trusted Publishing.

## Errors

Build failures, version mismatches, changed artifacts, and failed uploads raise without automatic retries. Before retrying an ambiguous upload, check RubyGems; see [recovery instructions](../RELEASING.md#verify-and-recover).
