# `RubyGemRelease::Version::References`

Decorates a version object to update explicitly selected files and patterns to the released version during `increment!`. Each regular expression must capture the version to replace as `version`:

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

The required `version:` argument is the wrapped object: [`RubyConstant`](ruby_constant.md), [`PlainText`](plain_text.md), or a custom object with `read`, `set!(value)`, and `increment!(from:)`. Objects missing any of them fail at construction. The decorator exposes only those three methods; `read` and `set!` delegate without updating references. Other methods of the wrapped object, such as `next_version`, are not exposed.

## References

The required `references:` argument maps literal file paths or Ruby `Dir.glob` patterns to arrays of patterns, expanded when `increment!` runs. Globs select files, exclude hidden names by default, and may match nothing; missing literal files raise an error. When selectors overlap, all their patterns apply in mapping order before the file is written. Each file receives only the patterns from selectors that match it. Configure only your project's references, and do not select the version value itself.

## Increment

`increment!` forwards `from:` and any additional keywords, such as `part:`, to the wrapped object. The wrapped version advances to the next development version, while matching references use `from:` (the released version), including on retries.

Reference files are read and their patterns applied before the wrapped increment, so unreadable files and invalid captures fail before the version changes, and no references are written if the wrapped increment rejects the input. Reference edits are then applied to each file's current content, so a selector that also matches the version file, such as a release comment in `version.rb`, preserves the new version. A file write failure after the increment can leave partial changes; retry using the same `from:` value.
