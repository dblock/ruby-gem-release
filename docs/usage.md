# Detailed Usage

Use the [standard workflow](workflow/ruby_gem.md) for the usual Ruby gem release sequence. Configure callbacks directly when you need different preparation or publication behavior. Both approaches use the same release objects and [GitHub Actions workflow](actions/release.md); choose one task installation per Rakefile.

## Project Files

For a version file such as `lib/example/version.rb`:

```ruby
# frozen_string_literal: true

module Example
  VERSION = '0.1.0'
end
```

Choose the matching changelog strategy: [`KeepAChangelog`](changelog/keep_a_changelog.md) for [this sample](../examples/keep_a_changelog/CHANGELOG.md), or [`Intridea`](changelog/intridea.md) for Next headings. Version files and changelog formats are never guessed.

## Standard Workflow

Add `ruby-gem-release` to the development dependencies and configure the Rakefile:

```ruby
require 'ruby-gem-release/workflow/ruby_gem'
require 'ruby-gem-release/changelog'

RubyGemRelease::Workflow::RubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
  changelog: RubyGemRelease::Changelog::KeepAChangelog.new
).install_tasks
```

This installs the before-release, publication, next development iteration, and workflow-context tasks. It builds once, verifies the archive, publishes to RubyGems before pushing the release commit and tag atomically, creates the hosted release, and increments the patch version for the next development iteration commit.

The default workflow releases the current version in your version file; it increments the patch version only afterward. An optional workflow `version` input asserts the prepared gemspec version rather than changing it. Use custom preparation callbacks when you need to set a different release version.

The package uses `GEMSPEC` or the only root gemspec. Repository, branch, and artifact directory use the existing checkout and workflow defaults. Missing or ambiguous selections fail instead of guessing.

## Object Overrides

Supply your own `package:`, `git:`, or `hosting:` object to customize an implementation without changing the release sequence. For example, disable GitHub Release creation while retaining RubyGems publication:

```ruby
RubyGemRelease::Workflow::RubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
  changelog: RubyGemRelease::Changelog::KeepAChangelog.new,
  hosting: nil
).install_tasks
```

Set `changelog: nil` for projects without a changelog; version incrementing and publication still run. Version and changelog choices are required constructor arguments, even when the changelog is explicitly disabled.

## Custom Callbacks

This is the full equivalent of the standard workflow. Keep this ordering to preserve artifact identity, concurrency checks, and package-before-tag publication:

```ruby
require 'ruby-gem-release/tasks'
require 'ruby-gem-release/changelog'
require 'ruby-gem-release/hosting/github_release'
require 'ruby-gem-release/package/ruby_gem'
require 'ruby-gem-release/source_control/git'

RubyGemRelease::Tasks.install do |tasks|
  version = RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION')
  changelog = RubyGemRelease::Changelog::KeepAChangelog.new
  package = RubyGemRelease::Package::RubyGem.new
  git = RubyGemRelease::SourceControl::Git.new
  github = RubyGemRelease::Hosting::GitHubRelease.new
  tasks.before_release do |release|
    changelog.release!(release.with_version(version.read))
  end
  tasks.publish do |release|
    git.commit!(release)
    package.build!(release)
    git.tag!(release)
    package.publish!(release)
    git.push!(release)
    github.publish!(release, package: package)
  end
  tasks.after_release do |release|
    next_release = release.with_next_version(version.increment!)
    changelog.prepare_next!(next_release)
    git.commit_next!(next_release)
    git.push!
  end
end
```

Use custom callbacks to set a release version during preparation, choose a different increment, or change the sequence. [`Tasks`](tasks.md) does not change files implicitly; each callback receives an immutable [`Release`](release.md) context. Changes to its version fields return copies rather than mutating the original.

## Actions Setup

Follow [Usage](../README.md#usage) to add the caller workflow, enable Trusted Publishing, and dispatch a release. Command overrides and all input defaults are documented in the [workflow reference](actions/release.md).

Both approaches publish when dispatched. Validate and build locally before authorizing a release. See [RELEASING.md](../RELEASING.md) before recovering from partial publication; never automatically retry an accepted upload or move a release tag.

## Configuration

### GitHub Actions Workflow

The reusable workflow provides the GitHub Actions environment for release callbacks, including setup, validation, authentication, and artifact preservation. Use its `with:` inputs to choose the gemspec, expected version, Ruby version, commands, and commit identity. Pin the workflow to a reviewed release or commit instead of `master` when available.

- [Release Workflow](actions/release.md): All inputs, defaults, permissions, commands, and recovery artifacts.
- [`Workflow::Context`](workflow/context.md): Ruby context capture and prepared-version checks used by the action workflow.
- [`Workflow::RubyGemsCredentials`](workflow/ruby_gems_credentials.md): Owner-bound OIDC authentication for first publication with a pending trusted publisher.

### Standard Workflows

Standard workflows wire the usual release sequence using your explicitly chosen version and changelog objects. Override package, Git, or hosting objects when needed; use custom callbacks for a different sequence.

- [`Workflow::RubyGem`](workflow/ruby_gem.md): Gem release preparation, publication, and next development iteration callbacks with conservative defaults.

### Version Objects

Version objects read, set, and increment the version stored in project files. Construct them locally in your callbacks; use your own objects for other file formats.

- [`Version::RubyConstant`](version/ruby_constant.md): Numeric Ruby constant versions, updated without evaluating the file.

### Release Callbacks

Callbacks define project-specific preparation, publication, and next development iteration work. The standard workflow installs them for you; [Detailed Usage](#custom-callbacks) shows manual configuration. Unregistered callbacks do nothing; exceptions fail the task. Custom callback code executes with release privileges and must be trusted.

- [`Tasks`](tasks.md): Registers `before_release`, `publish`, and `after_release` callbacks and their Rake tasks.
- [`Release`](release.md): Immutable version and date context passed to callbacks.

### Changelog Objects

Changelog objects prepare release headings and open the next development section while preserving unrelated Markdown. Choose the strategy matching your changelog format or use custom callbacks for other formats.

- [`Changelog::KeepAChangelog`](changelog/keep_a_changelog.md): Unreleased sections and version comparison references.
- [`Changelog::Intridea`](changelog/intridea.md): Next sections and a configured contribution placeholder.
- [`Changelog::Base`](changelog/base.md): Shared source-preserving implementation for concrete strategies.

### Package Objects

Package objects build, verify, and publish the exact release artifact.

- [`Package::RubyGem`](package/ruby_gem.md): Gem construction, artifact verification, and RubyGems publication.

### Source Control Objects

Source control objects manage release history independently of the repository's hosting provider.

- [`SourceControl::Git`](source_control/git.md): Release and next development iteration commits, tags, recovery bundles, branch checks, and atomic release pushes.

### Hosting Objects

Hosting objects publish release notes and attach package artifacts after the release tag is pushed. Set `hosting: nil` in the standard workflow, or omit the hosting publication call in custom callbacks, to disable hosted releases without disabling package publication.

- [`Hosting::GitHubRelease`](hosting/github_release.md): GitHub Releases with generated notes and the exact gem attached.
