# `RubyGemRelease::Release`

An immutable version and date value available through [callback execution contexts](execution_context.md) as `ctx.release` and passed directly to release operations. Strings and the date are copied and frozen along with the object.

## Version

`release.version` is the selected version before preparation, or the initial gemspec version when no version is selected. Later phases use the prepared gemspec version. `release.previous_version` retains the initial version independently. The required constructor argument `version:` is a string.

## Previous Version

`release.previous_version` retains the initial gemspec version across both phases. It can equal the released version. The required constructor argument `previous_version:` is a string.

## Next Development Iteration

`release.next_version` holds the version for the next development iteration and starts as `nil`. The optional constructor argument `next_version:` accepts a string.

The standard workflow records it after the next development iteration is committed and pushed, making it available to the success callback. Custom callbacks must call `ctx.record_next_version!(version)` explicitly; creating a release copy alone does not persist data across tasks.

## Date

`release.date` is a Ruby `Date`. The workflow captures it once in the configured `timezone` and retains it across both phases. UTC is the default; `America/New_York` uses Eastern Time with daylight saving changes. The constructor requires `date:` and does not perform timezone conversion.

## With Version

`release.with_version(version.read)` returns a new context containing the supplied version string, preserving every other field and leaving the original unchanged.

## With Next Development Iteration

`release.with_next_version(version.increment!)` returns a new context containing the supplied version for the next development iteration, preserving every other field and leaving the original unchanged.
