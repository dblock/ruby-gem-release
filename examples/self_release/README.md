# Releasing `ruby-gem-release` Itself

This project uses the standard workflow with three changes: its own changelog format, a version object that also updates version pins in README and documentation, and a chosen timezone. Everything else uses the defaults.

The real configuration is in the root [Rakefile](../../Rakefile), [`ReleaseVersion`](../../tasks/release_version.rb), and the [publish workflow](../../.github/workflows/publish.yml). This walkthrough explains those files.

## 1. Choose the Project Conventions

The Rakefile sets the version object and the [`Intridea` changelog format](../../docs/changelog/intridea.md):

```ruby
require 'ruby-gem-release/workflow/ruby_gem'
require 'ruby-gem-release/changelog'
require_relative 'tasks/release_version'

RubyGemRelease::Workflow::RubyGem.new(
  version: ReleaseVersion.build(path: 'lib/ruby-gem-release/version.rb', constant: 'VERSION', readme_path: 'README.md'),
  changelog: RubyGemRelease::Changelog::Intridea.new
).install_tasks
```

The root Rakefile also defines development tasks unrelated to releasing. Validation fails if the changelog has no pending notes and no heading for the release.

## 2. Decorate the Version Update

`ReleaseVersion.build` wraps a `Version::RubyConstant` in `Version::References` for `readme_path:` and every `docs/**/*.md` file. Its `increment!(from:)` does three things:

1. Pins this repository's action and reusable workflow references to the release version.
2. Increments the wrapped version from that same release version.
3. Writes the changed files and returns the next version.

Running it again changes nothing. For example, releasing `0.5.0` pins references to `v0.5.0` and sets the development version to `0.5.1`.

The workflow stages these edits together with the next changelog section. They go into the **next development commit**, after the release commit and tag are pushed, so the `v0.5.0` tag never contains them. No custom publication callback or file list is needed.

To adapt [the configuration](../../tasks/release_version.rb) to another project, change the version file path, documentation directory, and reference pattern.

## 3. Configure the Caller

The [publish workflow](../../.github/workflows/publish.yml) calls this repository's own reusable workflow:

```yaml
jobs:
  release:
    uses: ./.github/workflows/release.yml
    with:
      ruby-version: '4.0'
      version: ${{ inputs.version }}
      timezone: America/New_York
      rubygems-owner: ${{ vars.RUBYGEMS_OWNER_ID }}
      dry-run: ${{ inputs.dry-run }}
```

The full file also defines manual dispatch, the optional `version` and `dry-run` inputs, and the `contents: write` and `id-token: write` permissions. The timezone sets the release date and Git timestamp offsets, not registry timestamps. `RUBYGEMS_OWNER_ID` is a non-secret account ID needed only for a first release; it is not an API key.

Other repositories should use a released workflow reference, as in the [default setup](../../README.md#usage), not this local `uses:` path. They still need the [normal setup](../../RELEASING.md) for Trusted Publishing, environment protection, and branch permissions.

## 4. Follow the Standard Release Sequence

After an authorized dispatch (see [Releasing This Project](../../RELEASING.md#releasing-this-project)), the workflow runs the [standard steps](../../docs/actions/release.md#execution). The version bump and pin updates happen only after publication succeeds.

For bigger changes to execution, version selection, generated notes, or hosting, see the [GitLab and semantic-release example](../gitlab_semantic_release/README.md).
