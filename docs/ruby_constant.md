# `RubyGemRelease::Version::RubyConstant`

Reads and updates numeric `MAJOR.MINOR.PATCH` versions without evaluating the version file. Version objects are local to your configuration; [Tasks](tasks.md) requires no version strategy.

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

`version.set('1.2.3')` writes and returns the supplied version, preserving surrounding file content. Invalid versions or ambiguous assignments fail without writing the file.

## Increment

`version.increment!` writes and returns the next patch version. Use `part: :minor` or `part: :major` to increment those components and reset lower ones.
