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

This installs the validation, preparation, publication, next development iteration, success, failure, and workflow-context tasks. It builds once, verifies the archive, publishes to RubyGems before pushing the release commit and tag atomically, creates the hosted release, and increments the patch version for the next development iteration commit.

The default workflow releases the current version in your version file; it increments the patch version only afterward. Set the optional workflow `version` input to choose a different release version. The standard workflow calls your version object's `set!` method before preparing the changelog, preserving the initial version in the release context. Custom preparation callbacks retain control of their own file updates.

Configure optional `success:` and `failure:` lambdas on `Workflow::RubyGem.new` for notifications; success receives an execution context after the next development iteration succeeds, while failure receives a `RubyGemRelease::ReleaseFailure` with a phase, captured error when available, and execution context.

Before any preparation edits, `release:validate` checks the configured changelog for pending notes. An empty pending section skips the release successfully, even when a version is selected. Pass a `validate:` lambda returning `true` to proceed or `false` to skip when your project uses a different release decision; exceptions fail the release. Without a changelog, the standard decision is to proceed.

The package uses `GEMSPEC` or the only root gemspec. Repository, branch, and artifact directory use the existing checkout and workflow defaults. Missing or ambiguous selections fail instead of guessing.

## Object Overrides

Supply your own `package:`, `destination:`, `git:`, or `hosting:` object to customize an implementation without changing the release sequence. Packages own construction and verification; registry destinations own availability checks and uploads. For example, disable GitHub Release creation while retaining RubyGems publication:

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
require 'ruby-gem-release/destination/ruby_gems'
require 'ruby-gem-release/source_control/git'

package = RubyGemRelease::Package::RubyGem.new
destination = RubyGemRelease::Destination::RubyGems.new
RubyGemRelease::Tasks.install(package: package, destination: destination) do |tasks|
  version = RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION')
  changelog = RubyGemRelease::Changelog::KeepAChangelog.new
  git = RubyGemRelease::SourceControl::Git.new
  github = RubyGemRelease::Hosting::GitHubRelease.new
  tasks.validate { |_ctx| changelog.pending? }
  tasks.prepare do |ctx|
    release = ctx.release
    git.stage_changes! do
      version.set!(release.version) unless ENV.fetch('INPUT_VERSION', '').empty?
      changelog.release!(release.with_version(version.read))
    end
  end
  tasks.publish do |ctx|
    release = ctx.release
    destination.check_version!(name: package.name, version: release.version)
    git.commit!(release)
    package.build!(release)
    git.tag!(release)
    destination.publish!(release, package: package)
    git.push!(release)
    github.publish!(release, package: package)
  end
  tasks.bump do |ctx|
    release = ctx.release
    next_release = nil
    git.stage_changes! do
      next_release = release.with_next_version(version.increment!)
      changelog.prepare_next!(next_release)
    end
    git.commit_next!(next_release)
    git.push!
    ctx.record_next_version!(next_release.next_version)
  end
  tasks.success { |ctx| puts "Published #{ctx.release.version}" }
  tasks.failure do |failure|
    version = failure.context.release&.version || 'version unavailable'
    error = failure.error&.original_class || 'details unavailable'
    warn "Release failed during #{failure.phase} for #{version}: #{error}"
  end
end
```

Use custom callbacks to set a release version during preparation, choose a different increment, or change the sequence. [`Tasks`](tasks.md) does not change files implicitly; callbacks receive an [`ExecutionContext`](execution_context.md) containing an immutable [`Release`](release.md). Changes to release version fields return copies rather than mutating the original. Record the next development version explicitly after its operations succeed so later callbacks can read it.

Wrap custom preparation edits in `git.stage_changes!` as above; it checks for a clean checkout before the block and stages only the resulting changes, including custom README or version files. Both Actions interfaces also stage the trusted `prepare` command's outputs while resolving the prepared version, before testing. Publication never stages files: unexpected working tree or index changes after preparation fail instead of entering a release commit. Custom commands retain control of their operations, but must not stage unrelated validation or dependency output during publication.

Check `destination.check_version!(name: package.name, version: release.version)` before committing so a known duplicate stops before local release writes. Both Actions interfaces also check the prepared version during resolution using the configured package and destination. The RubyGems destination repeats the check using the built artifact's exact name and version before uploading; only HTTP 404 permits proceeding. For an earlier check, pass `version.read` before preparing files. See [Check Version](destination/ruby_gems.md#check-version).

## Actions Setup

Follow [Usage](../README.md#usage) to add the caller workflow, enable Trusted Publishing, and dispatch a release. Command overrides and all input defaults are documented in the [workflow reference](actions/release.md).

Both approaches publish when dispatched unless release validation skips successfully. Test and build locally before authorizing a release. See [RELEASING.md](../RELEASING.md) before recovering from partial publication; never automatically retry an accepted upload or move a release tag.

## Configuration

### GitHub Actions Workflow

The reusable workflow provides the GitHub Actions environment for release callbacks, including setup, validation, authentication, and artifact preservation. Use its `with:` inputs to choose the gemspec, release version, Ruby version, commands, and commit identity. Pin the workflow to a reviewed release or commit instead of `master` when available.

- [Release Workflow](actions/release.md): All inputs, defaults, permissions, commands, and recovery artifacts.
- [`Workflow::Environment`](workflow/environment.md): Ruby environment capture and prepared-version checks used by the action workflow.
- [`Workflow::RubyGemsCredentials`](workflow/ruby_gems_credentials.md): Owner-bound OIDC authentication for first publication with a pending trusted publisher.

### Standard Workflows

Standard workflows wire the usual release sequence using your explicitly chosen version and changelog objects. Override package, Git, or hosting objects when needed; use custom callbacks for a different sequence.

- [`Workflow::RubyGem`](workflow/ruby_gem.md): Gem release preparation, publication, and next development iteration callbacks with conservative defaults.

### Version Objects

Version objects read, set, and increment the version stored in project files. Construct them locally in your callbacks; use your own objects for other file formats.

- [`Version::RubyConstant`](version/ruby_constant.md): Numeric Ruby constant versions, updated without evaluating the file.

### Release Callbacks

Callbacks define project-specific preparation, publication, and next development iteration work. The standard workflow installs them for you; [Detailed Usage](#custom-callbacks) shows manual configuration. Unregistered callbacks do nothing; exceptions fail the task. Custom callback code executes with release privileges and must be trusted.

- [`Tasks`](tasks.md): Registers preparation, publication, next-development-iteration, success, and failure callbacks and their Rake tasks.
- [`ExecutionContext`](execution_context.md): Release data, current step, observed steps, configured workflow, and run metadata.
- [`Release`](release.md): Immutable version and date value used by release operations.

### Changelog Objects

Changelog objects prepare release headings and open the next development section while preserving unrelated Markdown. Choose the strategy matching your changelog format or use custom callbacks for other formats.

- [`Changelog::KeepAChangelog`](changelog/keep_a_changelog.md): Unreleased sections and version comparison references.
- [`Changelog::Intridea`](changelog/intridea.md): Next sections and a configured contribution placeholder.
- [`Changelog::Base`](changelog/base.md): Shared source-preserving implementation for concrete strategies.

### Package Objects

Package objects build, verify, and publish the exact release artifact.

- [`Package::RubyGem`](package/ruby_gem.md): Gem metadata, construction, and artifact verification.

### Registry Destinations

Registry destinations publish built packages independently of package construction and hosted releases. The default destination is RubyGems; custom destinations supply their own registry checks, uploads, and preconfigured credentials.

- [`Destination`](destination.md): Shared registry publication contract and authentication selection.
- [`Destination::RubyGems`](destination/ruby_gems.md): Public RubyGems version checks and exact-artifact publication.

### Source Control Objects

Source control objects manage release history independently of the repository's hosting provider.

- [`SourceControl::Git`](source_control/git.md): Release and next development iteration commits, tags, recovery bundles, branch checks, and atomic release pushes.

### Hosting Objects

Hosting objects publish release notes and attach package artifacts after the release tag is pushed. Set `hosting: nil` in the standard workflow, or omit the hosting publication call in custom callbacks, to disable hosted releases without disabling package publication.

- [`Hosting::GitHubRelease`](hosting/github_release.md): GitHub Releases with generated notes and the exact gem attached.
