# `RubyGemRelease::Changelog::Base`

Shared implementation for [`Intridea`](intridea.md) and [`KeepAChangelog`](keep_a_changelog.md). Use those concrete classes rather than constructing Base directly.

## Path

`path:` defaults to `'CHANGELOG.md'`.

## Release

`release!(release)` delegates the release version and date to the concrete format implementation.

Both built-in formats reject empty release notes before writing the file, with no opt-out. Only the current release section counts, ending at the next heading of equal or shallower depth. Blank lines, category headings, HTML comments or blocks, reference definitions, and the configured `Intridea` contribution placeholder are not release notes. Text, lists, quotes, and code with content count as notes. The error identifies the version and changelog path and asks you to add notes before retrying.

## Prepare Next

`prepare_next!(release)` delegates the released version and the version for the next development iteration to the concrete format implementation.

## Source Preservation

Uses `Commonmarker` to identify top-level headings and exclude code, HTML, and quoted blocks. Updates edit the original source rather than rendering the parsed document again, preserving unrelated formatting. Unix and Windows line endings are supported; mixed line endings or standalone carriage returns are rejected.

Hash-style release headings support depths 1 through 6, and their hash count is preserved. Headings inside nested blocks remain excluded. Multiple matching release headings are rejected even when their depths differ.
