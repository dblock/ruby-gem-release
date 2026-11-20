# `RubyGemRelease::Changelog::Intridea`

Updates changelog files with `## VERSION (Next)` and `## VERSION (YYYY/MM/DD)` headings, such as this project's [CHANGELOG.md](../../CHANGELOG.md). Inherits the shared source handling from [Base](base.md).

Release headings can use any Markdown depth from `#` through `######`, including `### VERSION (Next)`. Both phases preserve the matched heading's depth; no configuration or changelog reformatting is required. Deeper subsection headings stay inside the release section, which ends at the next heading of equal or shallower depth.

```ruby
require 'ruby-gem-release/changelog'

changelog = RubyGemRelease::Changelog::Intridea.new(path: 'CHANGELOG.md')
```

## Path

`path:` defaults to `'CHANGELOG.md'`. The class owns file reading and writing.

## Placeholder

`placeholder:` defaults to `'- Your contribution here.'`. Set `placeholder: '* Your contribution here.'` for the alternative bullet. It must be a single nonempty line, configured identically for both phases.

## Date

`date_format:` formats the date in the release heading. It defaults to `'%Y/%m/%d'`. Pass a `strftime` string, such as `date_format: '%Y-%m-%d'` for `## 1.0.0 (2026-11-07)`, or a callable that receives the release `Date` and returns a String for the text inside the parentheses. The formatted text must fit on one line and contain at least one digit, so headings such as `(Next)` cannot be written as releases. Otherwise `release!` raises before writing the file. Release headings written in any format are recognized as released, so changing the format does not duplicate existing releases; a parenthesized heading without a digit, such as `(TBD)`, is not.

## Sections

When the released section has headings one level below its release heading, `prepare_next!` carries those headings into the new Next section and adds the configured placeholder under each one. With no subsections, it creates the usual single placeholder. Old subsection notes are not copied.

Pass `sections:`, such as `sections: %w[Features Fixes]`, to name the subsections every Next section starts with. `release!` then removes subsection headings left without notes, so a fixes-only release has no empty `#### Features`, and `prepare_next!` always adds every configured section, including ones the previous release dropped. Names must be unique, nonempty, and on one line, and the release heading must be shallower than level six. Without `sections:`, empty subsections stay in the release and are carried forward as before.

## Release

During `release:validate`, placeholder-only or structural-only notes fail unless the selected release already has a heading. Invalid headings and missing placeholders also fail; multiple matching placeholders are allowed.

`changelog.release!(release)` replaces the Next heading with the [Release](../release.md) version and date, removing every matching placeholder from that section. Missing or duplicate headings, a missing placeholder, or an existing release heading fail without writing the file.

Placeholder-only sections and sections containing only headings, comments, or reference definitions also fail without writing. Add actual release notes to the Next section before retrying; older releases do not count. There is no empty-release opt-out. See [Release Notes](base.md#release) for what counts as content.

## Prepare Next

`changelog.prepare_next!(release)` inserts a Next section using `release.next_version` and the configured placeholder above the section for `release.version`. It requires exactly one matching release section and reuses an existing matching Next section. `release!` likewise reuses the selected version's existing release heading.
