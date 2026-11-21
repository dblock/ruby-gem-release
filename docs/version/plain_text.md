# `RubyGemRelease::Version::PlainText`

Reads and updates a file, such as `VERSION`, that holds only a `MAJOR.MINOR.PATCH` version and an optional final line ending, which updates keep. Prereleases and `VERSION.yml` are not supported.

```ruby
require 'ruby-gem-release/version/plain_text'

version = RubyGemRelease::Version::PlainText.new(path: 'VERSION')
version.read
version.set!('1.2.3')
version.increment!(from: '1.2.3')
```

`path:` defaults to `VERSION`. `set!` and `increment!` write and return the new version. `increment!` bumps the patch, or `part: :major` or `part: :minor`. Pass the release version as `from:` so retries write the same result. Invalid versions raise without writing.

Wrap it in [`References`](references.md) to update version references in other files during the next development bump.
