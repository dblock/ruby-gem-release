# `RubyGemRelease::Version::PlainText`

Reads and updates a file containing a numeric `MAJOR.MINOR.PATCH` version, such as `VERSION`. The file must contain only the version and an optional final Unix or Windows line ending, which updates preserve. Prereleases and `VERSION.yml` are not supported.

```ruby
require 'ruby-gem-release/version/plain_text'

version = RubyGemRelease::Version::PlainText.new(path: 'VERSION')
version.read
version.set!('1.2.3')
version.increment!(from: '1.2.3')
```

`path:` defaults to `VERSION`. `increment!` writes the next patch version, or a major or minor version when passed `part: :major` or `part: :minor`. Pass the release version as `from:` for repeatable retries. Invalid current or requested versions fail without writing.

Wrap the version in [`References`](ruby_constant.md#release-references) to update selected release references during the next development bump.
