# Detailed Usage

Use the [standard workflow](workflow/ruby_gem.md), or configure callbacks for a different sequence. Both use the same release objects and [Actions interface](actions/release.md); install tasks only once.

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

This validates and prepares the release, publishes the verified gem, pushes the release commit and tag, creates the hosted release, and prepares the next patch version.

The default releases the checked-in version; optional `version` selects another through the version object's `set!`. The initial version remains in the context. Custom preparation callbacks own their file updates.

Configure optional `success:` and `failure:` lambdas on `Workflow::RubyGem.new` for notifications; success receives an execution context after the next development iteration succeeds, while failure receives a `RubyGemRelease::ReleaseFailure` with a phase, captured error when available, and execution context.

Before edits, `release:validate` requires pending notes or an existing heading for the selected release. Otherwise it raises, even with an explicit version. Override with a `validate:` lambda that raises on failure; returning `false` also fails. Without a changelog, validation passes.

Use [lifecycle hooks](workflow/hooks.md) to add checks or project edits without replacing callbacks. Preparation hooks run inside trusted Git staging; see the [example](../examples/lifecycle_hooks/Rakefile).

The package uses `GEMSPEC_PATH` or the only root gemspec. Repository, branch, and artifact directory use the existing checkout and workflow defaults. Missing or ambiguous selections fail instead of guessing.

When adding project-specific release customizations, use optional `ruby-gem-release/rspec` helpers to test the real workflow in a disposable consumer repository and inspect its commits and release-managed files; see [Testing Custom Workflows](testing.md).

## Object Overrides

Override `package:`, `destination:`, `git:`, `hosting:`, or `provider:` without changing the sequence. For example, disable hosted releases while retaining RubyGems publication:

```ruby
RubyGemRelease::Workflow::RubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
  changelog: RubyGemRelease::Changelog::KeepAChangelog.new,
  hosting: nil
).install_tasks
```

Set `changelog: nil` for projects without a changelog; version incrementing and publication still run. Version and changelog choices are required constructor arguments, even when the changelog is explicitly disabled.

## Custom Callbacks

For a genuinely different sequence, configure replacement callbacks explicitly. Individual project customizations should use lifecycle hooks instead. Keep this ordering to preserve artifact identity, concurrency checks, and package-before-tag publication:

```ruby
require 'ruby-gem-release/workflow/ruby_gem'
require 'ruby-gem-release/changelog'
require 'ruby-gem-release/hosting/github_release'
require 'ruby-gem-release/package/ruby_gem'
require 'ruby-gem-release/destination/ruby_gems'
require 'ruby-gem-release/source_control/git'

provider = RubyGemRelease::ExecutionProvider.current
package = RubyGemRelease::Package::RubyGem.new(directory: provider.directory)
destination = RubyGemRelease::Destination::RubyGems.new
version = RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION')
changelog = RubyGemRelease::Changelog::KeepAChangelog.new
git = RubyGemRelease::SourceControl::Git.new(directory: provider.directory)
github = RubyGemRelease::Hosting::GitHubRelease.new
workflow = RubyGemRelease::Workflow::RubyGem.new(version: version, changelog: changelog, package: package, destination: destination,
                                                 git: git, hosting: github, provider: provider)
RubyGemRelease::Tasks.install(workflow: workflow, package: package, destination: destination, provider: provider) do |tasks|
  tasks.validate { |ctx| changelog.released?(ctx.release.version) || changelog.pending? }
  tasks.prepare do |ctx|
    release = ctx.release
    git.stage_changes! do
      version.set!(release.version) unless provider.fetch('INPUT_VERSION', '').empty?
      changelog.release!(release.with_version(version.read))
    end
  end
  tasks.publish do |ctx|
    release = ctx.release
    workflow.checkpoint!(ctx)
    destination.publish!(release, package: package)
    git.push!(release)
    github.publish!(release, package: package)
  end
  tasks.bump do |ctx|
    release = ctx.release
    next_release = nil
    git.stage_changes! do
      next_release = release.with_next_version(version.increment!(from: release.version))
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

Callbacks receive an [`ExecutionContext`](execution_context.md) containing an immutable [`Release`](release.md); version changes return copies. [`Tasks`](tasks.md) does not edit files. Record the next development version only after its operations succeed.

Wrap trusted preparation edits in `git.stage_changes!`. Resolution also stages custom `prepare` command outputs before testing. Publication never stages: later working-tree or index changes fail rather than entering the release commit.

Pass the configured `workflow:` so `release:workflow:checkpoint` can build and preserve artifacts before publication. Each publishing task enforces its own postcondition; an already accepted exact archive succeeds only on matching checksum. See [reruns](../RELEASING.md#verify-and-recover).

## Actions Setup

Follow [Usage](../README.md#usage) to add the caller workflow, enable Trusted Publishing, and dispatch a release. Command overrides and all input defaults are documented in the [workflow reference](actions/release.md).

Both approaches publish when dispatched unless validation fails. All custom commands must be idempotent for the current checkout and inputs and preserve the [rerun contract](../RELEASING.md#verify-and-recover); never overwrite an immutable registry version or move a release tag.

## Configuration

### GitHub Actions Workflow

Use `with:` inputs for the gemspec, version, runtime, commands, and commit identity. Pin a reviewed release or commit, not `master`.

- [Release Workflow](actions/release.md): All inputs, defaults, permissions, commands, and recovery artifacts.
- [`Workflow::Environment`](workflow/environment.md): Ruby environment capture and prepared-version checks used by the action workflow.
- [`Workflow::RubyGemsCredentials`](workflow/ruby_gems_credentials.md): RubyGems OIDC authentication, with an optional owner assertion for first publication with a pending trusted publisher.

### Standard Workflows

Standard workflows wire the usual release sequence using your explicitly chosen version and changelog objects. Override package, Git, or hosting objects when needed; use custom callbacks for a different sequence.

- [`Workflow::RubyGem`](workflow/ruby_gem.md): Gem release preparation, publication, and next development iteration callbacks with conservative defaults.
- [`Workflow::SemanticRubyGem`](workflow/semantic_ruby_gem.md): Commit-driven decisions, release-history-based versions, and generated notes.

### Version Objects

Version objects read, set, and increment the version stored in project files. Construct them locally in your callbacks; use your own objects for other file formats.

- [`Version::RubyConstant`](version/ruby_constant.md): Numeric Ruby constant versions, updated without evaluating the file.

### Release Callbacks

Callbacks define project-specific preparation, publication, and next development iteration work. The standard workflow installs them for you; [Detailed Usage](#custom-callbacks) shows manual configuration. Unregistered callbacks do nothing; exceptions fail the task. Custom callback code executes with release privileges and must be trusted.

- [`Tasks`](tasks.md): Registers preparation, publication, next-development-iteration, success, and failure callbacks and their Rake tasks.
- [`ExecutionContext`](execution_context.md): Release data, current step, observed steps, configured workflow, and run metadata.
- [`ExecutionProvider`](execution_provider.md): Execution-platform services, with a GitHub Actions implementation and a provider-neutral base.
- [`Release`](release.md): Immutable version and date value used by release operations.

### Changelog Objects

Changelog objects prepare release headings and open the next development section while preserving unrelated Markdown. Choose the strategy matching your changelog format or use custom callbacks for other formats.

- [`Changelog::KeepAChangelog`](changelog/keep_a_changelog.md): Unreleased sections and version comparison references.
- [`Changelog::Intridea`](changelog/intridea.md): Next sections and a configured contribution placeholder.
- [`Changelog::Base`](changelog/base.md): Shared source-preserving implementation for concrete strategies.
- [`Changelog::Generated`](workflow/semantic_ruby_gem.md#notes-and-changelog): Dated sections from persisted semantic notes.

### Package Objects

Package objects build and verify artifacts; destinations publish them.

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
