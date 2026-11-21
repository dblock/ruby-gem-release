# `RubyGemRelease::Changelog::KeepAChangelog`

Updates a [Keep a Changelog](https://keepachangelog.com/) file with `## [Unreleased]` and `## [VERSION] - YYYY-MM-DD` headings. See the [sample changelog](../../examples/keep_a_changelog/CHANGELOG.md) and [Rakefile](../../examples/keep_a_changelog/Rakefile). Shared behavior is in [Base](base.md).

```ruby
require 'ruby-gem-release/changelog'

changelog = RubyGemRelease::Changelog::KeepAChangelog.new(path: 'CHANGELOG.md')
```

Headings can use any level from `#` to `######`; edits keep it. By default, category headings and older releases are left alone.

## Path

`path:` defaults to `'CHANGELOG.md'`.

## Contribution Templates

If your Unreleased section has a prompt line or a fixed category list, set `placeholder:` and `sections:`:

```ruby
changelog = RubyGemRelease::Changelog::KeepAChangelog.new(
  placeholder: '* Your contribution here.',
  sections: %w[Added Changed Deprecated Removed Fixed Security]
)
```

With either set, `release!` removes placeholder lines and empty categories, keeping real notes, code, older releases, and links. Validation ignores placeholders the same way. `prepare_next!` adds each category in order, one level below the release heading, with the placeholder if set.

`placeholder:` defaults to `nil` and must be one nonempty line. `sections:` defaults to `[]`; names must be unique, nonempty, and one line. With the defaults, notes are untouched and new Unreleased sections are empty.

## Release

`changelog.release!(release)` replaces the `[Unreleased]` heading with the [Release](../release.md) version and date. Before writing anything, it raises on a missing or duplicate Unreleased heading, an invalid comparison link, or a section with no real notes (only categories, comments, or links). Add notes and retry; older releases do not count and there is no empty-release option. See [Release Notes](base.md#release).

`release:validate` runs the same checks without writing. Empty notes fail unless the version is already released.

## Prepare Next

`changelog.prepare_next!(release)` adds an Unreleased section above the `release.version` section. It needs a valid `release.next_version` and exactly one matching section. It reuses an existing Unreleased section, and `release!` reuses an existing release heading, so both are safe to retry.

## Reference Links

An optional `[Unreleased]: https://github.com/owner/repo/compare/v1.0.0...HEAD` link is updated to compare the new release with the branch, and a link for the new version is added. URL, tag prefix, branch, older links, and other references are kept.

Links must be one `http://` or `https://` URL ending in `VERSION...BRANCH`, with an optional tag prefix such as `v`. Other formats, duplicate `[Unreleased]` links, or an existing link for the new version raise without writing. `prepare_next!` checks that `[Unreleased]` starts at the released version. Handle other link formats in your own callback.
