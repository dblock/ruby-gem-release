# Read-Only Release Notes

`Changelog::Notes` reads an already-reviewed release section without editing it. The default matches Intridea date headings. Supply a callable returning an anchored regular expression to match a different project format:

```ruby
require 'ruby-gem-release/changelog/notes'

notes = RubyGemRelease::Changelog::Notes.new(
  path: 'History.md',
  heading: ->(version) { %r{\A## #{Regexp.escape(version)} / \d{4}-\d{2}-\d{2}\z} },
  expand_references: true
).read('8.0.0')
```

Parsing requires the optional Commonmarker dependency. Exactly one real Markdown heading must match; fenced examples do not count. Extraction stops at the next heading of the same or higher level and rejects empty notes. Original line endings and subsection formatting are retained; surrounding whitespace is stripped.

With `expand_references: true`, resolved reference links and images become inline links, including definitions elsewhere in the source. Code, unresolved references, and existing inline links remain unchanged. The source file is never written. Pass the resulting string as the release's `notes:` for hosted publication.
