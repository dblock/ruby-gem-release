# `RubyGemRelease::Version::RubyConstant`

Reads and updates numeric `MAJOR.MINOR.PATCH` versions without evaluating the version file. Version objects are local to your configuration; [Tasks](../tasks.md) requires no version strategy.

```ruby
require 'ruby-gem-release/version/ruby_constant'

version = RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION')
```

## Path

The required `path:` argument identifies the version file.

## Constant

The required `constant:` argument names the Ruby constant, such as `'VERSION'`. The file must contain exactly one quoted assignment to that constant.

## Read

`version.read` returns the current version string.

## Set

`version.set!('1.2.3')` writes and returns the supplied version, preserving surrounding file content. Invalid versions or ambiguous assignments fail without writing the file.

## Increment

`version.increment!` writes and returns the next patch version. Use `part: :minor` or `part: :major` to increment those components and reset lower ones.

Pass `from: release.version` to `increment!` to write the same development version on every attempt instead of incrementing the current file twice. `next_version(part: :patch, from: read)` computes that value without editing files.

## Release References

`RubyGemRelease::Version::References` extends `RubyConstant` to update explicitly selected files and patterns to the released version during `increment!`. Each regular expression must capture the version to replace as `version`:

```ruby
require 'ruby-gem-release/version/references'

version = RubyGemRelease::Version::References.new(
  path: 'lib/example/version.rb', constant: 'VERSION',
  references: {
    'README.md' => [%r{owner/example@v(?<version>\d+\.\d+\.\d+)(?![\w.+-])}],
    'docs/**/*.md' => [/gem 'example', '(?<version>\d+\.\d+\.\d+)'/]
  }
)
```

Keys are literal file paths or Ruby `Dir.glob` patterns, expanded when `increment!` runs. Globs select files, exclude hidden names by default, and may match nothing; missing literal files raise an error. When selectors overlap, all their patterns apply in mapping order before the file is written. Each file receives only the patterns from selectors that match it.

Configure only your project's references. The version constant advances to the next development version, while matching references use `from:` (the released version), including on retries. Invalid versions or unreadable files fail before the version constant changes.
