# `RubyGemRelease::Release`

An immutable context passed to [release callbacks](tasks.md). Strings and the date are copied and frozen along with the object.

## Version

`release.version` is the current gemspec version before preparation and the prepared version after publication. The required constructor argument `version:` is a string.

## Previous Version

`release.previous_version` retains the initial gemspec version across both phases. It can equal the released version. The required constructor argument `previous_version:` is a string.

## Next Development Iteration

`release.next_version` holds the version for the next development iteration and starts as `nil`. The optional constructor argument `next_version:` accepts a string.

## Date

`release.date` is a Ruby `Date`. The workflow captures it once in UTC and retains it across both phases. The constructor requires `date:`.

## With Version

`release.with_version(version.read)` returns a new context containing the supplied version string, preserving every other field and leaving the original unchanged.

## With Next Development Iteration

`release.with_next_version(version.increment!)` returns a new context containing the supplied version for the next development iteration, preserving every other field and leaving the original unchanged.

## Dry Run

The optional constructor argument `dry_run:` defaults to `false`. `release.dry_run?` tells publishers and Git pushes to skip remote writes. Lifecycle tasks set it from `DRY_RUN`; both copy methods preserve it.
