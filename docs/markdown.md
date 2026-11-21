# Updating Markdown Sections

`RubyGemRelease::Markdown::Section` edits the body of one Markdown section, so hooks can keep your own wording and version links current:

```ruby
require 'ruby-gem-release/markdown/section'

stable = RubyGemRelease::Markdown::Section.new(
  path: 'README.md', heading: '## Stable Release'
)

workflow.before(:validate) { |_ctx| stable.validate! }
workflow.after(:prepare_release) do |ctx|
  stable.replace!("You're reading the documentation for version #{ctx.release.version}.")
end
```

`heading:` is the exact, full heading line, with one to six `#`. Exactly one top-level heading must match; headings in code, quotes, and HTML do not count. Missing or duplicate headings raise before writing; `validate!` checks only.

`replace!(body)` replaces everything after the heading up to the next heading of the same or higher level, including subsections. The rest of the file is kept, `body` line endings are converted to the file's, and repeating it is safe. Mixed or unsupported line endings raise.

`gsub!(pattern, replacement)` replaces matching text in the body only:

```ruby
stable.gsub!(/version \d+\.\d+\.\d+/, 'version 0.2.0')
```

It works like `String#gsub!`: a string or regular expression, with capture references in the replacement. All matches in the body are replaced, including subsections and code; the heading and other sections are unchanged. Formatting and the final newline are kept. With no match it returns `nil` and writes nothing.

The [lifecycle hooks example](../examples/lifecycle_hooks/release_notes.rb) uses this for its stable and development README text. Test that wording and your release behavior in your own [custom workflow specs](testing.md).
