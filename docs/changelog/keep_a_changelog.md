# `RubyGemRelease::Changelog::KeepAChangelog`

Updates [Keep a Changelog](https://keepachangelog.com/) files with `## [Unreleased]` and `## [VERSION] - YYYY-MM-DD` headings. See the [sample changelog](../../examples/keep_a_changelog/CHANGELOG.md) and [Rakefile](../../examples/keep_a_changelog/Rakefile). Inherits shared source handling from [Base](base.md).

Release headings can use any Markdown depth from `#` through `######`. Both phases preserve the matched heading's depth. By default, category headings and history are unchanged; optional contribution templates clean empty categories and restore the configured template.

```ruby
require 'ruby-gem-release/changelog'

changelog = RubyGemRelease::Changelog::KeepAChangelog.new(path: 'CHANGELOG.md')
```

## Path

`path:` defaults to `'CHANGELOG.md'`. The class owns file reading and writing.

## Contribution Templates

Set `placeholder:` to ignore a project's contribution prompt during validation and remove matching lines when releasing. Set `sections:` to restore a complete category template for the next release, including categories that had no changes:

```ruby
changelog = RubyGemRelease::Changelog::KeepAChangelog.new(
  placeholder: '* Your contribution here.',
  sections: %w[Added Changed Deprecated Removed Fixed Security]
)
```

With either option enabled, releasing removes empty category headings while preserving real notes, code examples, history, and comparison references. Validation uses the same cleanup in memory; placeholder-only notes are not a release. Next-section preparation adds each configured category in order with the configured placeholder, if any. Categories are one heading level below the release heading.

Both options are optional: `placeholder:` defaults to `nil` and `sections:` to `[]`, retaining the existing unmodified-note behavior and empty next section. A placeholder must be one nonempty line, and section names must be unique nonempty lines. Existing next sections are reused rather than overwritten.

## Release

During `release:validate`, empty or structural-only notes fail unless the selected release already has a heading. Invalid headings or comparison references also fail.

`changelog.release!(release)` replaces the single Unreleased heading using the [Release](../release.md) version and date. Missing or duplicate headings, or an existing release heading, fail without writing the file.

An empty Unreleased section, including category headings, comments, or comparison links without notes, fails before any file or reference update is written. Add actual release notes before retrying; older releases do not count. There is no empty-release opt-out. See [Release Notes](base.md#release) for what counts as content.

## Prepare Next

`changelog.prepare_next!(release)` inserts an Unreleased section above the section for `release.version`. It requires a valid `release.next_version` and exactly one matching release section, and reuses an existing Unreleased section. `release!` likewise reuses the selected version's existing release heading.

## Reference Links

An optional `[Unreleased]: https://github.com/owner/repo/compare/v1.0.0...HEAD` definition is updated to compare the new release against the development branch. A released-version comparison definition is added, preserving the URL, tag prefix, branch, historical links, and unrelated references.

Comparison definitions must use a single `http://` or `https://` URL ending in `VERSION...BRANCH`, with an optional tag prefix before the numeric version. Unsupported URLs, duplicate Unreleased references, or existing references for the new release fail without writing the file. Next-section preparation verifies that the Unreleased comparison starts at the released version. Use custom callback code for other link formats.
