# Package Collections and Prebuilt Archives

`Package::Collection` implements the normal build, version, and verification interface for an explicit, nonempty array of packages. All packages must have the same release version, with unique gem identities and attachment filenames. Give each built package its own artifact directory.

```ruby
require 'ruby-gem-release/package/collection'
require 'ruby-gem-release/package/prebuilt'

packages = RubyGemRelease::Package::Collection.new(
  packages: [
    RubyGemRelease::Package::Prebuilt.new(path: '/retained/example-1.2.3.gem',
                                          sha256: ruby_digest, name: 'example', version: '1.2.3'),
    RubyGemRelease::Package::Prebuilt.new(path: '/retained/example-1.2.3-java.gem',
                                          sha256: java_digest, name: 'example', version: '1.2.3', platform: 'java')
  ]
)
```

Prebuilt packages verify the supplied checksum, expected name/version/platform, filename, and optional `audit:` every time. `build!` verifies rather than rebuilding or replacing them. Supply the reviewed digest explicitly from the original build; the API does not discover artifacts, restore state, or trust a digest calculated from an unknown input during publication.

Use the collection as the standard workflow's `package:`, or pass it to `Destination::RubyGems#publish!` and `Hosting::GitHubRelease#publish!`. Hosting attaches all verified archives. RubyGems verifies every local artifact and checks every registry identity before the first upload, rejecting conflicting published bytes even for later members. Uploads remain sequential and cannot be atomic; on repetition, exact existing publications are accepted and only missing members are uploaded.

Custom destinations receiving a collection must implement equivalent all-member verification and publication. `artifacts(release)` exposes the verified paths; `packages` exposes the frozen member list. A collection deliberately has no singular `artifact` or `gemspec`.
