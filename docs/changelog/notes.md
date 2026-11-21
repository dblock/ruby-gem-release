# Read-Only Release Notes

`Changelog::Notes` reads one released section of a changelog, without editing it, for use as hosted release notes.

```ruby
require 'ruby-gem-release/changelog/notes'

notes = RubyGemRelease::Changelog::Notes.new(
  path: 'History.md',
  heading: ->(version) { %r{\A## #{Regexp.escape(version)} / \d{4}-\d{2}-\d{2}\z} },
  expand_references: true
).read('8.0.0')
```

`path:` defaults to `'CHANGELOG.md'`. `heading:` defaults to Intridea date headings; for other formats, pass a callable returning an anchored regular expression. It needs the optional `commonmarker` gem.

`read(version)` returns the section body. Exactly one real heading must match; code examples do not count. The section ends at the next heading of the same or higher level. Empty notes raise. Line endings and formatting are kept, and outer whitespace is stripped.

With `expand_references: true` (default `false`), resolved reference links and images become inline, even if defined elsewhere. Code, unresolved references, and inline links are unchanged. Trailing link definitions, such as Keep a Changelog comparison links, are dropped.

Pass the result as the release's `notes:`.
