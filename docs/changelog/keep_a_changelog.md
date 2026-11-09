# `RubyGemRelease::Changelog::KeepAChangelog`

Updates [Keep a Changelog](https://keepachangelog.com/) files with `## [Unreleased]` and `## [VERSION] - YYYY-MM-DD` headings. See the [sample changelog](../../examples/keep_a_changelog/CHANGELOG.md) and [Rakefile](../../examples/keep_a_changelog/Rakefile). Inherits shared source handling from [Base](base.md).

Release headings can use any Markdown depth from `#` through `######`. Both phases preserve the matched heading's depth, leaving category headings and history unchanged. No configuration or changelog reformatting is required.

```ruby
require 'ruby-gem-release/changelog'

changelog = RubyGemRelease::Changelog::KeepAChangelog.new(path: 'CHANGELOG.md')
```

## Path

`path:` defaults to `'CHANGELOG.md'`. The class owns file reading and writing.

## Release

The standard workflow first checks `pending?` during `release:validate`; empty or structural-only sections skip successfully without writing. Invalid headings or comparison references still fail.

`changelog.release!(release)` replaces the single Unreleased heading using the [Release](../release.md) version and date. Missing or duplicate headings, or an existing release heading, fail without writing the file.

An empty Unreleased section, including category headings, comments, or comparison links without notes, fails before any file or reference update is written. Add actual release notes before retrying; older releases do not count. There is no empty-release opt-out. See [Release Notes](base.md#release) for what counts as content.

## Prepare Next

`changelog.prepare_next!(release)` inserts an Unreleased section above the section for `release.version`. It requires a valid `release.next_version`, exactly one matching release section, and no existing Unreleased section.

## Reference Links

An optional `[Unreleased]: https://github.com/owner/repo/compare/v1.0.0...HEAD` definition is updated to compare the new release against the development branch. A released-version comparison definition is added, preserving the URL, tag prefix, branch, historical links, and unrelated references.

Comparison definitions must use a single `http://` or `https://` URL ending in `VERSION...BRANCH`, with an optional tag prefix before the numeric version. Unsupported URLs, duplicate Unreleased references, or existing references for the new release fail without writing the file. Next-section preparation verifies that the Unreleased comparison starts at the released version. Use custom callback code for other link formats.
