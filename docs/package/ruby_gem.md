# `RubyGemRelease::Package::RubyGem`

Owns gem metadata, building, and artifact verification independently of the publication destination. Commands use argument arrays rather than shell interpolation. Registry operations belong to [`Destination`](../destination.md).

## Gemspec

`RubyGem.new(gemspec: 'example.gemspec')` selects an explicit specification; otherwise it uses `GEMSPEC` or the only root gemspec. Missing or ambiguous selections fail. The standard workflow uses this package during capture and resolution, exporting its absolute `gemspec` path.

## Directory

The optional `directory:` defaults to a nonempty `RELEASE_DIRECTORY` or a new temporary directory. The standard workflow supplies the execution provider's directory explicitly; Actions capture also exports it for manual callbacks and subsequent processes. `directory` returns this location. Keep it outside the working tree so build artifacts do not enter release commits.

## Version

`version` reads the gemspec version in a fresh Ruby process so callback edits are visible even if the specification was previously loaded.

## Name

`name` reads the current gemspec name in a fresh Ruby process, including custom preparation edits. Destinations use this name for checks before building; publication must use the actual built artifact's identity.

## Build

`build!(release)` builds `release.gem` once, checks its version, and records its name, version, and checksum in `release.json`. It returns the package filename. Call it after the release commit and before tagging; `Git#tag!` rejects build mutations in the checkout.

## Artifact

`artifact(release)` verifies the preserved version and digest and returns a copy named `NAME-VERSION.gem`. Registry destinations and hosted releases use that exact archive without rebuilding. A new instance using the same directory can reopen it for recovery.

## Errors

Build failures, version mismatches, and changed artifacts raise. The package does not contact a registry or upload files; see [`Destination::RubyGems`](../destination/ruby_gems.md) for publication and duplicate-version safeguards.
