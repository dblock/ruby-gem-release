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

This installs the before-release, publication, next-version, and workflow-context tasks. It builds once, verifies the archive, publishes to RubyGems before pushing the release commit and tag atomically, creates the hosted release, and increments the patch version for the next development commit.

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
    changelog.prepare_next!(release.with_next_version(version.increment!))
    git.commit_next!(release)
    git.push!
  end
end
```

Use custom callbacks to set a release version during preparation, choose a different increment, or change the sequence. [`Tasks`](tasks.md) does not change files implicitly; each callback receives an immutable [`Release`](release.md) context. Changes to its version fields return copies rather than mutating the original.

## Actions Setup and Dry Runs

Follow [Usage](../README.md#usage) to add the caller workflow, enable Trusted Publishing, and dispatch a release. Command overrides and all input defaults are documented in the [workflow reference](actions/release.md).

Both approaches invoke all callbacks in dry-run mode. The supplied classes perform local commits, builds, and tags while suppressing uploads and remote pushes. Custom code must honor the release context's dry-run flag. See [RELEASING.md](../RELEASING.md) before recovering from partial publication; never automatically retry an accepted upload or move a release tag.
