# `RubyGemRelease::Changelog::KeepAChangelog`

Updates [Keep a Changelog](https://keepachangelog.com/) files with `## [Unreleased]` and `## [VERSION] - YYYY-MM-DD` headings. See the [sample changelog](../../examples/keep_a_changelog/CHANGELOG.md) and [Rakefile](../../examples/keep_a_changelog/Rakefile). Inherits shared source handling from [Base](base.md).

```ruby
require 'ruby-gem-release/changelog'

changelog = RubyGemRelease::Changelog::KeepAChangelog.new(path: 'CHANGELOG.md')
```

## Path

`path:` defaults to `'CHANGELOG.md'`. The class owns file reading and writing.

## Release

`changelog.release!(release)` replaces the single Unreleased heading using the [Release](../release.md) version and date. Missing or duplicate headings, or an existing release heading, fail without writing the file.

## Prepare Next

`changelog.prepare_next!(release)` inserts an Unreleased section above the section for `release.version`. It requires a valid `release.next_version`, exactly one matching release section, and no existing Unreleased section.

## Reference Links

An optional `[Unreleased]: https://github.com/owner/repo/compare/v1.0.0...HEAD` definition is updated to compare the new release against the development branch. A released-version comparison definition is added, preserving the URL, tag prefix, branch, historical links, and unrelated references.

Comparison definitions must use a single `http://` or `https://` URL ending in `VERSION...BRANCH`, with an optional tag prefix before the numeric version. Unsupported URLs, duplicate Unreleased references, or existing references for the new release fail without writing the file. Next-section preparation verifies that the Unreleased comparison starts at the released version. Use custom callback code for other link formats.
