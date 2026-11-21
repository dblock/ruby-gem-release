# `RubyGemRelease::Version::RubyConstant`

Reads and updates a numeric `MAJOR.MINOR.PATCH` version assigned to a Ruby constant, without running the file. You only need a version object for your own configuration; [Tasks](../tasks.md) does not require one.

```ruby
require 'ruby-gem-release/version/ruby_constant'

version = RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION')
```

## Path

`path:` is required: the version file.

## Constant

`constant:` is required, such as `'VERSION'`. The file must have exactly one quoted assignment to it.

## Read

`version.read` returns the version string.

## Set

`version.set!('1.2.3')` writes and returns the version, leaving the rest of the file unchanged. An invalid version or ambiguous assignment raises without writing.

## Increment

`version.increment!` writes and returns the next patch version. `part: :minor` or `part: :major` bumps those and resets lower parts.

Pass `from: release.version` so retries write the same version instead of bumping twice. `next_version(part: :patch, from: read)` computes it without writing.

## Release References

Wrap it in [`References`](references.md) to update version references in other files during the next development bump.
