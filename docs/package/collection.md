# Package Collections and Prebuilt Archives

`Package::Collection` releases several gems together, such as ruby and Java builds of one version. It has the usual package methods, so use it anywhere a package goes. `Package::Prebuilt` wraps an archive that was already built.

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

`packages:` must be a nonempty array. Members must share one version and have unique gem identities and filenames. Give each built package its own directory.

A prebuilt package checks its SHA256, name, version, platform, filename, and optional `audit:` every time it is used. `build!` only checks; it never rebuilds. Pass the reviewed digest from the original build. The library never searches for archives, restores state, or trusts a digest computed from an unknown file.

## Build Manifests

Load a manifest (`release.json`) from an original `Package::RubyGem` build, stating the expected identity:

```ruby
package = RubyGemRelease::Package::Prebuilt.from_manifest(
  manifest: '/retained/java/release.json',
  name: 'example',
  version: '1.2.3',
  platform: 'java',
  audit: audit
)
```

The manifest must match the given identity. The digest comes from the manifest, read once, and the archive must sit beside it under its standard filename; a missing archive raises. `platform:` defaults to `ruby`; `audit:` is optional. Use only a trusted original manifest, never digests from downloaded archives.

## Publication

Use the collection as the workflow's `package:`, or pass it to `Destination::RubyGems#publish!` and `Hosting::GitHubRelease#publish!`. Hosting attaches every archive. RubyGems checks every local archive and registry entry before the first upload, and raises if any published gem has different bytes. Uploads are sequential, not atomic; a retry accepts exact existing gems and uploads only missing ones.

A custom destination must check and publish every member the same way. `artifacts(release)` returns the checked paths; `packages` returns the frozen member list. A collection has no single `artifact` or `gemspec`.
