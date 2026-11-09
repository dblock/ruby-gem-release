# `RubyGemRelease::Changelog::Base`

Shared implementation for [`Intridea`](intridea.md) and [`KeepAChangelog`](keep_a_changelog.md). Use those concrete classes rather than constructing Base directly.

## Path

`path:` defaults to `'CHANGELOG.md'`.

## Pending Notes

`pending?` reads the current unreleased section without writing files. It returns `true` when actual notes exist and `false` for an empty or structural-only section, ignoring historical notes and the configured `Intridea` placeholder. Missing or duplicate release headings, invalid line endings, malformed comparison links, and missing or duplicate placeholders raise errors rather than reporting no changes.

Default validation requires an existing selected release or pending notes; otherwise it raises.

## Release

`released?(version)` returns whether that version has a release heading; duplicates raise. `release!(release)` reuses an existing heading unchanged, or delegates the version and date to the concrete format implementation.

New releases require nonempty notes. Only the current section counts, ending at the next heading of equal or shallower depth. Blank lines, category headings, HTML comments or blocks, reference definitions, and the configured `Intridea` contribution placeholder are not notes. Text, lists, quotes, and code with content count. Errors identify the version and changelog path.

## Prepare Next

`prepare_next!(release)` delegates the released version and the version for the next development iteration to the concrete format implementation.

## Source Preservation

Uses `Commonmarker` to identify top-level headings and exclude code, HTML, and quoted blocks. Updates edit the original source rather than rendering the parsed document again, preserving unrelated formatting. Unix and Windows line endings are supported; mixed line endings or standalone carriage returns are rejected.

Hash-style release headings support depths 1 through 6, and their hash count is preserved. Headings inside nested blocks remain excluded. Multiple matching release headings are rejected even when their depths differ.
