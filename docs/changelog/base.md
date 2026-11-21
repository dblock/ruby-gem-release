# `RubyGemRelease::Changelog::Base`

The shared parent of [`Intridea`](intridea.md) and [`KeepAChangelog`](keep_a_changelog.md). Use those classes, not `Base`.

## Path

`path:` defaults to `'CHANGELOG.md'`.

## Pending Notes

`pending?` returns whether the unreleased section has real notes, without writing. Older releases and the `Intridea` placeholder do not count. A malformed file raises instead of returning `false`: missing or duplicate release headings or placeholders, bad comparison links, or invalid line endings.

The standard workflow's validation raises unless the version already has a release heading or `pending?` is `true`.

## Release

`released?(version)` returns whether that version has a release heading. Duplicates raise.

`release!(release)` turns the unreleased heading into a release heading with the version and date. If the version is already released, it changes nothing, so retries are safe.

A new release needs real notes in the unreleased section, which ends at the next heading of the same or higher level. Text, lists, quotes, and nonempty code count. Blank lines, category headings, HTML, link definitions, and the `Intridea` placeholder do not. Errors name the version and changelog path.

## Notes

`notes(version)` returns a released section's body without editing the file. Like [read-only notes](notes.md) with `expand_references: true`, it makes reference links inline and drops trailing link definitions. Unreleased, missing, duplicate, or empty sections raise. The [standard workflow](../workflow/ruby_gem.md#hosting) passes the result to hosting.

## Prepare Next

`prepare_next!(release)` adds an unreleased section for `release.next_version` above the `release.version` section.

## Source Preservation

Parsing uses `Commonmarker`. Only top-level headings count; headings in code, HTML, quotes, or other nested blocks are ignored. Edits change the original text in place, so other formatting is kept.

- Unix and Windows line endings work. Mixed endings or lone carriage returns raise.
- Release headings can use one to six `#`; edits keep the level.
- Two headings for one version raise, even at different levels.
