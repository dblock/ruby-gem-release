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

## Release

`changelog.release!(release)` replaces the single Next heading with the [Release](../release.md) version and date, removing exactly one placeholder from that section. Missing or duplicate headings and placeholders, or an existing release heading, fail without writing the file.

## Prepare Next

`changelog.prepare_next!(release)` inserts a Next section using `release.next_version` and the configured placeholder above the section for `release.version`. It requires exactly one matching release section and no existing Next section.
