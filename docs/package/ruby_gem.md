# `RubyGemRelease::Package::RubyGem`

Owns gem metadata, building, and artifact verification independently of the publication destination. Commands use argument arrays rather than shell interpolation. Registry operations belong to [`Destination`](../destination.md).

## Gemspec

`RubyGem.new(gemspec: 'example.gemspec')` selects an explicit specification; otherwise it uses `GEMSPEC_PATH` or the only root gemspec. Missing or ambiguous selections fail. The standard workflow uses this package during capture and resolution, exporting its absolute `gemspec` path.

## Directory

The optional `directory:` defaults to a nonempty `RELEASE_DATA_DIR` or a new temporary directory. The standard workflow supplies the execution provider's directory explicitly; Actions capture also exports it for manual callbacks and subsequent processes. `directory` returns this location. Keep it outside the working tree so build artifacts do not enter release commits.

## Version

`version` reads the gemspec version in a fresh Ruby process so callback edits are visible even if the specification was previously loaded.

## Build

`build!(release)` overwrites `release.gem`, checks its version, and records its name, version, and checksum in `release.json`. It returns the package filename. Call it after the release commit and before tagging; `Git#tag!` rejects build mutations in the checkout.

Builds use `SOURCE_DATE_EPOCH` for the gemspec date and archive timestamps. Workflow capture supplies the committer timestamp of the original source commit, not the generated release commit; an explicit value takes precedence. Direct builds without capture or an override retain RubyGems' fixed default `1980-01-02T00:00:00Z`.

Reproduce a release from the same source commit: equivalent files in another commit can have a different timestamp. Toolchains, generated files, gemspecs, and signing inputs must also remain stable. No previous archive is needed; partial output is overwritten. `built?(release)` verifies an existing archive and manifest without building.

The standard Actions workflow builds at checkpoint and again during publication. Each build writes the same reproducible archive and digest manifest; direct builds overwrite prior output.

## Artifact

`artifact(release)` verifies the built name, version, and digest and returns a copy named `NAME-VERSION.gem`. Registry destinations and hosted releases use those exact bytes.

Verification checks the retained archive against the manifest and validates its gem metadata before publication. `artifact(release)` copies the verified canonical archive to its name-and-version path.

## Errors

Build failures, version mismatches, and changed artifacts raise. The package does not contact a registry or upload files; see [`Destination::RubyGems`](../destination/ruby_gems.md) for publication and duplicate-version safeguards.
