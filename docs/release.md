# `RubyGemRelease::Release`

A frozen value holding the version, date, and notes of the release in progress. Callbacks read it as `ctx.release` from their [execution context](execution_context.md), and release operations take it as an argument. Strings and the date are copied and frozen; the `with_*` methods return copies.

## Version

`release.version` is the version being released: before preparation, the selected version or else the initial gemspec version; later, the prepared gemspec version. The constructor requires `version:` as a string.

## Gemspec Version

`release.gemspec_version` is the gemspec version when the workflow started, before any selected version or preparation. It can equal `release.version`, and it is not the last published version. The constructor requires `gemspec_version:` as a string.

## Next Development Iteration

`release.next_version` is the version for development after the release. It starts as `nil`; the optional `next_version:` takes a string.

The standard workflow sets it after the next-version commit is pushed, so the success callback can read it. Custom callbacks must call `ctx.record_next_version!(version)`; a new release copy alone does not reach later tasks.

## Date

`release.date` is a Ruby `Date`, required as `date:`. The workflow captures it once in the configured `timezone` (default UTC; `America/New_York` follows Eastern daylight saving time) and uses it in every phase. The constructor does no time zone conversion.

## Notes

`release.notes` is optional Markdown passed as `notes:`. [Semantic workflows](workflow/semantic_ruby_gem.md) save generated notes and pass them to the changelog and hosting. Manual workflows leave it `nil`, so GitHub generates hosted notes. Copies keep it; `release.with_notes(notes)` replaces it.

## With Version

`release.with_version(version.read)` returns a copy with the given version, leaving the original unchanged.

## With Next Development Iteration

`release.with_next_version(version.increment!(from: release.version))` returns a copy with the given next development version, leaving the original unchanged.
