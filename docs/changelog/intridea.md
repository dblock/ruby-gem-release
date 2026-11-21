# `RubyGemRelease::Changelog::Intridea`

Updates a changelog with `## VERSION (Next)` and `## VERSION (YYYY/MM/DD)` headings, like this project's [CHANGELOG.md](../../CHANGELOG.md). Shared behavior is in [Base](base.md).

```ruby
require 'ruby-gem-release/changelog'

changelog = RubyGemRelease::Changelog::Intridea.new(path: 'CHANGELOG.md')
```

Headings can use any level from `#` to `######`; edits keep it. Deeper headings belong to the release section.

## Path

`path:` defaults to `'CHANGELOG.md'`.

## Placeholder

`placeholder:` defaults to `'- Your contribution here.'`; use `'* Your contribution here.'` for the other bullet. It must be one nonempty line, and the same when releasing and preparing the next section. Contributors may delete it once there are notes. The same text with a different bullet raises rather than being published.

## Date

`date_format:` sets the date inside the parentheses. It defaults to `'%Y/%m/%d'`. Pass a `strftime` string, such as `'%Y-%m-%d'` for `## 1.0.0 (2026-11-07)`, or a callable that takes the `Date` and returns a String. The result must be one line with at least one digit, or `release!` raises before writing; so `(Next)` can never become a release.

Any parenthesized heading with a digit counts as released, so changing the format does not duplicate old releases. `(TBD)` does not count.

## Sections

By default, `prepare_next!` copies the last release's subsection headings (one level down) into the new Next section, each with a placeholder. Notes are not copied, and empty subsections stay in the release.

With `sections:`, such as `%w[Features Fixes]`, every Next section starts with those subsections. `release!` removes the empty ones, so a fixes-only release has no empty `#### Features`. Names must be unique, nonempty, and one line, and the release heading must be level five or shallower.

## Release

`changelog.release!(release)` replaces the Next heading with the [Release](../release.md) version and date and removes placeholder lines. Without writing, it raises on a missing or duplicate Next heading, a placeholder with the wrong bullet, or a section with no real notes (only placeholders, headings, comments, or link definitions). Add notes and retry; older releases do not count and there is no empty-release option. See [Release Notes](base.md#release).

`release:validate` runs the same checks without writing. Placeholder-only notes fail unless the version is already released. Several placeholders are allowed.

## Prepare Next

`changelog.prepare_next!(release)` adds a Next section for `release.next_version`, with the placeholder, above the `release.version` section. Exactly one section must match `release.version`; a Next section for another version raises. It reuses a matching Next section, and `release!` reuses an existing release heading, so both are safe to retry.
