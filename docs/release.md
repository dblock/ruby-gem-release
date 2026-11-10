# `RubyGemRelease::Release`

An immutable version and date value available through [callback execution contexts](execution_context.md) as `ctx.release` and passed directly to release operations. Strings and the date are copied and frozen along with the object.

## Version

`release.version` is the selected version before preparation, or the initial gemspec version when no version is selected. Later phases use the prepared gemspec version. `release.gemspec_version` retains the initial version independently. The required constructor argument `version:` is a string.

## Gemspec Version

`release.gemspec_version` retains the gemspec version captured at workflow start, before any version override or preparation. It can equal `release.version`; it does not identify the last published release. The required constructor argument `gemspec_version:` is a string.

## Next Development Iteration

`release.next_version` holds the version for the next development iteration and starts as `nil`. The optional constructor argument `next_version:` accepts a string.

The standard workflow records it after the next development iteration is committed and pushed, making it available to the success callback. Custom callbacks must call `ctx.record_next_version!(version)` explicitly; creating a release copy alone does not persist data across tasks.

## Date

`release.date` is a Ruby `Date`. The workflow captures it once in the configured `timezone` and retains it across both phases. UTC is the default; `America/New_York` uses Eastern Time with daylight saving changes. The constructor requires `date:` and does not perform timezone conversion.

## Notes

`release.notes` is an optional copied, frozen Markdown string supplied through `notes:`. [Semantic workflows](workflow/semantic_ruby_gem.md) persist generated notes and pass the same body to changelog and hosting operations. Manual workflows leave it `nil`, retaining platform-generated hosted-release notes. Version copies preserve it.

## With Version

`release.with_version(version.read)` returns a new context containing the supplied version string, preserving every other field and leaving the original unchanged.

## With Next Development Iteration

`release.with_next_version(version.increment!(from: release.version))` returns a new context containing the next development version, preserving every other field and leaving the original unchanged.
