# Updating Markdown Sections

Use `RubyGemRelease::Markdown::Section` to replace a section's body while keeping project-specific wording and version links in your hooks:

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

`heading:` is the complete, exact heading line, with one to six leading `#` characters. There must be exactly one matching top-level Markdown heading; headings inside code, quotes, and HTML examples do not count. Missing or duplicate headings raise before writing.

`replace!` replaces everything after that heading through the next equal-or-shallower heading, including nested subsections. It preserves surrounding source, normalizes the replacement's line endings to the file, and accepts repeated replacement. Mixed or unsupported line endings are rejected.

Use `gsub!(pattern, replacement)` to replace matching text without replacing the whole body:

```ruby
stable.gsub!(/version \d+\.\d+\.\d+/, 'version 0.2.0')
```

Like `String#gsub!`, the pattern can be a string or regular expression, and replacement strings support capture references. All matches within the body are replaced, including matches in nested subsections and code examples; the heading and surrounding sections remain unchanged. Existing formatting and the final newline are preserved, and inserted line endings follow the file's style. With no matches, it returns `nil` without writing. Missing or duplicate section headings still raise.

The [lifecycle-hooks example](../examples/lifecycle_hooks/release_notes.rb) uses this helper for its stable and development README text. Keep assertions about that wording and the project's release behavior in the project's [custom workflow specs](testing.md).
