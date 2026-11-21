# `RubyGemRelease::Version::References`

Wraps a version object so that `increment!` also updates chosen version references, such as install snippets in a README, to the released version. Each regular expression must capture the version as `version`:

```ruby
require 'ruby-gem-release/version/ruby_constant'
require 'ruby-gem-release/version/references'

version = RubyGemRelease::Version::References.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
  references: {
    'README.md' => [%r{owner/example@v(?<version>\d+\.\d+\.\d+)(?![\w.+-])}],
    'docs/**/*.md' => [/gem 'example', '(?<version>\d+\.\d+\.\d+)'/]
  }
)
```

## Version

`version:` is required: a [`RubyConstant`](ruby_constant.md), [`PlainText`](plain_text.md), or your own object with `read`, `set!(value)`, and `increment!(from:)`. A missing method raises at construction. The wrapper has only those three methods; `read` and `set!` pass through without touching references, and others such as `next_version` are not available.

## References

`references:` is required. It maps file paths or `Dir.glob` patterns to arrays of regular expressions, expanded when `increment!` runs. Globs skip hidden files and may match nothing; a missing literal path raises. A file matched by several selectors gets all their patterns, in order. List only your project's references, not the version value itself.

## Increment

`increment!` passes `from:` and other keywords, such as `part:`, to the wrapped object, which moves to the next development version. References are set to `from:`, the released version, including on retries.

It reads all reference files and applies the patterns before the version changes, so unreadable files and unmatched captures raise first, and nothing is written if the wrapped `increment!` raises. Edits apply to each file's current content, so a pattern that also matches the version file keeps the new version. A write error after that can leave partial changes; retry with the same `from:`.
