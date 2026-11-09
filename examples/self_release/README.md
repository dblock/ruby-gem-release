# Releasing `ruby-gem-release` Itself

This project uses the standard workflow with three small customizations: its existing changelog format, a version object that also updates README pins, and a caller-selected timezone. GitHub Actions, RubyGems Trusted Publishing, package construction, Git publication, and hosted releases retain their defaults.

The working implementation lives in the root [Rakefile](../../Rakefile), [`ReleaseVersion`](../../tasks/release_version.rb), and [publish workflow](../../.github/workflows/publish.yml). This walkthrough explains those files rather than maintaining a second release configuration.

## 1. Choose the Project Conventions

The Rakefile supplies the version object and the existing [`Intridea` changelog format](../../docs/changelog/intridea.md):

```ruby
require 'ruby-gem-release/workflow/ruby_gem'
require 'ruby-gem-release/changelog'
require_relative 'tasks/release_version'

RubyGemRelease::Workflow::RubyGem.new(
  version: ReleaseVersion.new(path: 'lib/ruby-gem-release/version.rb', constant: 'VERSION', readme_path: 'README.md'),
  changelog: RubyGemRelease::Changelog::Intridea.new
).install_tasks
```

The root Rakefile also installs development tasks; those are unrelated to release customization. The standard validation still skips publication when the pending changelog contains no release notes.

## 2. Extend Only the Version Update

The project-local `ReleaseVersion` subclasses `Version::RubyConstant`, inheriting `read` and `set!`. Its constructor accepts an additional `readme_path:`. Its `increment!` implementation reads the version just released, replaces this repository's action and reusable-workflow version pins in the README, calls `super` to increment the version file, writes the README, and returns the next version.

For example, publishing `0.5.0` results in README references to `v0.5.0` and a development version of `0.5.1`. These are deliberately different values.

The standard workflow wraps `increment!` and changelog preparation in the same trusted Git staging boundary. Both files therefore belong to the **next development iteration commit**, after the release commit and tag have already been published. The `v0.5.0` tag does not receive a later README edit. No custom publication callback or hard-coded staging list is necessary.

Use the [actual subclass](../../tasks/release_version.rb) as the complete implementation. When adapting it to another project, change both the version-file path and the repository-specific README reference pattern.

## 3. Configure the Caller

The project's [publish workflow](../../.github/workflows/publish.yml) calls its own reusable workflow:

```yaml
jobs:
  release:
    uses: ./.github/workflows/release.yml
    with:
      ruby-version: '4.0'
      version: ${{ inputs.version }}
      timezone: America/New_York
      rubygems-owner: ${{ vars.RUBYGEMS_OWNER_ID }}
```

The complete caller defines manual dispatch, its optional version input, and the required contents-write and identity-token permissions. The timezone controls the release date and Git timestamp offsets, not registry timestamps. The non-secret owner variable identifies the RubyGems account for first publication; it is not an API key.

Other repositories should use a released workflow reference as shown in the [default setup](../../README.md#usage), rather than copying this project's local `uses:` reference. Trusted Publishing, environment protection, and branch permissions still need the [normal setup](../../RELEASING.md).

## 4. Follow the Standard Release Sequence

After authorized manual dispatch, the workflow captures and validates the checkout, checks for pending notes, prepares the selected version and changelog, resolves the prepared gemspec, and runs tests. It then authenticates, commits and builds the release, tags locally, publishes the exact gem, pushes the release commit and tag, and creates the GitHub Release.

Only after publication succeeds does it increment the version, update README pins, prepare the next changelog section, and push the next development iteration commit. Standard recovery artifacts and failure handling remain in place.

For more extensive changes to execution, release decisions, generated notes, and hosting, continue with the [GitLab and semantic-release example](../gitlab_semantic_release/README.md).
