# Detailed Usage

Use the [standard workflow](workflow/ruby_gem.md), or [custom callbacks](#custom-callbacks) for different release steps. Both use the same [Actions interface](actions/release.md). Install the tasks only once.

To publish an existing signed tag whose changes are already reviewed and merged, use the [reviewed workflow](workflow/reviewed_ruby_gem.md). It makes no commits, tags, pushes, or version bumps, and supports stable branches and package collections.

## Project Files

For a version file such as `lib/example/version.rb`:

```ruby
# frozen_string_literal: true

module Example
  VERSION = '0.1.0'
end
```

Pick the changelog class that matches your format: [`KeepAChangelog`](changelog/keep_a_changelog.md) for [this sample](../examples/keep_a_changelog/CHANGELOG.md), or [`Intridea`](changelog/intridea.md) for `Next` headings. Neither is guessed.

## Standard Workflow

Add `ruby-gem-release` and `commonmarker ~> 2.10` (only needed for Markdown changelogs) to your development dependencies. On JRuby, use `changelog: nil` or your own changelog class:

```ruby
require 'ruby-gem-release/workflow/ruby_gem'
require 'ruby-gem-release/changelog'

RubyGemRelease::Workflow::RubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
  changelog: RubyGemRelease::Changelog::KeepAChangelog.new
).install_tasks
```

A release validates, updates the version file and changelog, publishes the gem, pushes the release commit and tag, creates the GitHub Release, and bumps the patch version (or the part set by [`next_version:`](workflow/ruby_gem.md#next-version)).

It releases the checked-in version unless you pass the optional `version` input, which is written with the version object's `set!`. The context keeps the original version. Custom preparation callbacks must update files themselves.

**Validation.** Before any edits, `release:validate` fails unless the changelog has pending notes or already has a heading for this version, even with an explicit version. To replace it, pass a `validate:` lambda that raises (or returns `false`) on failure. Without a changelog, validation passes.

**Notifications.** Pass optional `success:` and `failure:` lambdas to `Workflow::RubyGem.new`. `success` gets the execution context after the next development version is pushed. `failure` gets a `RubyGemRelease::ReleaseFailure` with the failed phase, the error when available, and the execution context.

**Hooks.** Use [lifecycle hooks](workflow/hooks.md) to add checks or file edits. Edits made by preparation hooks go into the release commit; see the [example](../examples/lifecycle_hooks/Rakefile).

**Defaults.** The gem is built from `GEMSPEC_PATH` or the only gemspec in the root. The repository, branch, and artifact directory come from the checkout and workflow. Missing or ambiguous choices fail.

**Testing.** The optional `ruby-gem-release/rspec` helpers run the real workflow in a throwaway repository, so you can check the commits and files your customizations produce. See [Testing Custom Workflows](testing.md).

### Bundler Release Tasks

`bundler/gem_tasks` and `Bundler::GemHelper.install_tasks` add a `rake release` task that builds, tags, pushes, and publishes from your machine with your own RubyGems credentials. Its helpers `release:rubygem_push` and `release:source_control_push` can also be run directly. To make the workflow the only way to release, replace all three after Bundler installs them:

```ruby
%w[release release:rubygem_push release:source_control_push].each do |name|
  Rake::Task[name].clear
  task(name) { abort "#{name} is disabled; releases run through GitHub Actions" }
end
```

`clear` also removes their prerequisites, so nothing is built or tagged before the task aborts. The Bundler `build` and `install` tasks still work, and this gem's `release:*` tasks are unaffected.

## Object Overrides

You can replace `package:`, `destination:`, `git:`, `hosting:`, or `provider:` and keep the same steps. For example, turn off GitHub Releases but keep publishing to RubyGems:

```ruby
RubyGemRelease::Workflow::RubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
  changelog: RubyGemRelease::Changelog::KeepAChangelog.new,
  hosting: nil
).install_tasks
```

Without a changelog, set `changelog: nil`; version bumps and publication still run. Both `version:` and `changelog:` are required, even when the changelog is `nil`.

## Custom Callbacks

Write callbacks only when you need different release steps; for smaller changes, use lifecycle hooks. Keep this order: it ensures the published gem is the one that was built and checked, catches concurrent changes, and publishes the gem before the tag:

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

- Callbacks receive an [`ExecutionContext`](execution_context.md) with an immutable [`Release`](release.md); version changes return a copy.
- [`Tasks`](tasks.md) does not edit files; your callbacks do.
- Call `record_next_version!` only after the next-version commit is pushed.
- Wrap preparation edits in `git.stage_changes!`. Files changed by a custom `prepare` command are staged before tests run.
- Publication never stages files; later changes fail the release instead of entering the commit.
- Pass `workflow:` so `release:workflow:checkpoint` can build and preserve artifacts before publication.
- Each publishing task checks its own result. On a rerun, an existing gem counts as published only if its checksum matches. See [reruns](../RELEASING.md#verify-and-recover).

## Actions Setup

Follow [Usage](../README.md#usage) to set up and dispatch a release. The [workflow reference](actions/release.md) lists every input, default, and command override.

Dispatching publishes unless validation fails. Custom commands must be safe to rerun with the same checkout and inputs ([reruns](../RELEASING.md#verify-and-recover)). Never overwrite a published version or move a release tag.

## Configuration

### GitHub Actions Workflow

Set the gemspec, version, Ruby version, commands, and commit author under `with:`. Pin a release or commit, not `master`.

- [Release Workflow](actions/release.md): All inputs, defaults, permissions, commands, and recovery artifacts.
- [`Workflow::Environment`](workflow/environment.md): Records release settings at the start and checks the prepared version.
- [`Workflow::RubyGemsCredentials`](workflow/ruby_gems_credentials.md): RubyGems Trusted Publishing login, with an optional owner ID for a gem's first release.

### Standard Workflows

Standard workflows run the usual steps with your version and changelog objects. You can swap the package, Git, or hosting objects.

- [`Workflow::RubyGem`](workflow/ruby_gem.md): Prepares, publishes, and bumps the version, with safe defaults.
- [`Workflow::SemanticRubyGem`](workflow/semantic_ruby_gem.md): Picks versions and writes notes from Conventional Commits and past releases.

### Version Objects

Version objects read, set, and bump the version in your project files. For other formats, write your own object with `read`, `set!(value)`, and `increment!(from:)`.

- [`Version::RubyConstant`](version/ruby_constant.md): A numeric version in a Ruby constant, updated without running the file.
- [`Version::PlainText`](version/plain_text.md): A numeric version in a plain text file, such as `VERSION`.
- [`Version::References`](version/references.md): Wraps another version object and also updates version references in other files, such as README pins, to the released version during the next development bump.

### Release Callbacks

Callbacks do the release work. The standard workflow installs them; [Custom Callbacks](#custom-callbacks) shows how to set them up by hand. An unregistered callback does nothing, and an exception fails the task. Callback code runs with release credentials, so it must be trusted.

- [`Tasks`](tasks.md): Registers callbacks and their Rake tasks.
- [`ExecutionContext`](execution_context.md): Release data, current and previous steps, the workflow, and run details.
- [`ExecutionProvider`](execution_provider.md): Access to the CI platform, with a GitHub Actions implementation and a generic base.
- [`Release`](release.md): The immutable version and date of a release.

### Changelog Objects

Changelog objects add the release heading and open a section for the next version, leaving the rest of the file unchanged.

- [`Changelog::KeepAChangelog`](changelog/keep_a_changelog.md): Unreleased sections and version comparison references.
- [`Changelog::Intridea`](changelog/intridea.md): Next sections and a configured contribution placeholder.
- [`Changelog::Base`](changelog/base.md): Shared base class for the formats above.
- [`Changelog::Generated`](workflow/semantic_ruby_gem.md#notes-and-changelog): Dated sections from notes generated by semantic releases.

### Package Objects

Package objects build and verify the gem; destinations publish it.

- [`Package::RubyGem`](package/ruby_gem.md): Reads gem metadata, builds the gem, and verifies it.

### Registry Destinations

Destinations publish the built gem to a registry. The default is RubyGems. A custom destination brings its own version checks, uploads, and credentials.

- [`Destination`](destination.md): The base class for registries, including how they log in.
- [`Destination::RubyGems`](destination/ruby_gems.md): Checks whether a version exists on RubyGems and publishes the exact built gem.

### Source Control Objects

Source control objects create release commits and tags, whatever service hosts the repository.

- [`SourceControl::Git`](source_control/git.md): Release and next-version commits, tags, recovery bundles, branch checks, and all-or-nothing pushes.

### Hosting Objects

Hosting objects create a release page with notes and the gem after the tag is pushed. To turn this off, set `hosting: nil`, or leave out the hosting call in custom callbacks.

- [`Hosting::GitHubRelease`](hosting/github_release.md): A GitHub Release with changelog or generated notes and the exact gem attached.
