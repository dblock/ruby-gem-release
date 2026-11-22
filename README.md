<img src="assets/logo.png" alt="A faceted ruby gemstone with an upward release arrow" width="160">

# Ruby Gem Release

[![Gem Version](https://img.shields.io/gem/v/ruby-gem-release.svg)](https://rubygems.org/gems/ruby-gem-release) [![Test](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml/badge.svg)](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml) [![Coverage Status](https://coveralls.io/repos/github/dblock/ruby-gem-release/badge.svg?branch=master)](https://coveralls.io/github/dblock/ruby-gem-release?branch=master)

**Release your Ruby gem from GitHub Actions without maintaining custom release scripts or storing a RubyGems API key.**

Implements [Releases as Code](https://code.dblock.org/2026/11/12/releases-as-code.html) for Ruby gems. You start a GitHub Actions workflow, and it:

- runs your tests,
- publishes the gem to RubyGems,
- updates the changelog (optional),
- creates a Git tag and a GitHub Release,
- bumps the version for the next development iteration.

See also [npm-package-release](https://github.com/dblock/npm-package-release) and [rust-crate-release](https://github.com/dblock/rust-crate-release).

You need Ruby 3.3+, GitHub Actions, and RubyGems Trusted Publishing.

## Usage

### 1. Configure Your Gem

Add `ruby-gem-release` and `commonmarker ~> 2.10` (needed only for Markdown changelogs) to your development dependencies. Then install the release tasks in your Rakefile, naming your version file and changelog format:

```ruby
require 'ruby-gem-release/workflow/ruby_gem'
require 'ruby-gem-release/changelog'

RubyGemRelease::Workflow::RubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
  changelog: RubyGemRelease::Changelog::KeepAChangelog.new
).install_tasks
```

With these defaults, a release:

- uses the only gemspec in the repository root,
- fails if the changelog has no pending notes,
- moves the pending notes under a new release heading,
- publishes to RubyGems and GitHub Releases,
- bumps the patch version afterwards (pass `next_version: :minor` or `:major` to [bump another part](docs/workflow/ruby_gem.md#next-version)),
- dates the release in UTC.

If your Rakefile also installs the Bundler gem tasks, disable the local Bundler `release` tasks so nobody can publish around the workflow. See [Bundler Release Tasks](docs/usage.md#bundler-release-tasks).

Every release starts by checking that the checkout is clean, and Ruby setup installs gems inside it. Add what it writes to `.gitignore`, leaving out the lockfile if you commit it:

```gitignore
/vendor/bundle/
/.bundle/
/Gemfile.lock
```

With a [release Gemfile](docs/actions/release.md#release-gemfile), ignore its lockfile instead, such as `/gemfiles/release.gemfile.lock`. A [dry run](docs/actions/release.md#dry-run) fails and lists any lines that are missing.

### 2. Add the Release Workflow

Copy the [sample workflow](examples/.github/workflows/release.yml) to `.github/workflows/release.yml` and set your Ruby version:

```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      version:
        description: Optional release version overriding the checked-in version.
        type: string
        required: false
      rubygems-owner:
        description: RubyGems account ID for first publication; omit for an existing gem.
        type: string
        required: false

permissions:
  contents: write
  id-token: write

jobs:
  release:
    uses: dblock/ruby-gem-release/.github/workflows/release.yml@v0.9.0
    with:
      ruby-version: '3.3'
      version: ${{ inputs.version }}
      rubygems-owner: ${{ inputs.rubygems-owner }}
```

### 3. Enable Trusted Publishing

Trusted Publishing lets GitHub Actions publish to RubyGems without a stored API key.

1. In your GitHub repository, open **Settings → Environments** and create an environment named `release`. Or run `gh api --method PUT repos/{owner}/{repo}/environments/release` from your repository directory.
2. On RubyGems, open the [pending trusted publishers page](https://rubygems.org/profile/oidc/pending_trusted_publishers) for a new gem, or your gem's **Trusted publishers** page (for example `https://rubygems.org/gems/example/trusted_publishers`) for an existing gem.
3. Create a [trusted publisher](https://guides.rubygems.org/trusted-publishing/#using-reusable-workflows) with your gem's repository, workflow filename `release.yml`, and environment `release`.
4. Set the separate workflow repository fields to `dblock` and `ruby-gem-release`. This tells RubyGems to trust this project's reusable workflow.

To check the setup without releasing, run a [dry run](docs/actions/release.md#dry-run).

Anyone with write access can now dispatch a release, without admin access or RubyGems credentials. The `release` environment alone restricts nothing. To require approval from a maintainer, configure [required reviewers and deployment branches](RELEASING.md#maintainer-approved-publication).

### 4. Make a Release

Your branch rules must allow the workflow to push release commits and tags ([branch permissions](RELEASING.md#one-time-setup)); each release checks this before publishing. Run your tests, review the changes, then dispatch from your default branch. Dispatching starts a real release; with required reviewers, it waits for approval.

Do not merge into the default branch while a release runs. If that happens, see [recovery](docs/actions/release.md#default-branch-advanced-during-publication).

**First release:** pass your numeric RubyGems account ID, shown on the Pending Trusted Publishers page, as `rubygems-owner`. This account will own the new gem:

```sh
gh workflow run release.yml -f rubygems-owner=YOUR_ACCOUNT_ID
```

**Later releases:** omit `rubygems-owner`. The trusted publisher is still required:

```sh
gh workflow run release.yml
```

To release a different version, enter it in the dispatch form or pass `-f version=1.2.3`. The workflow writes it to your version file, and the next development version is bumped from it.

For a real-world example of adding this to an existing gem, see [ruby-link-checker #26](https://github.com/dblock/ruby-link-checker/pull/26).

## Extending the Workflow

Replace only what you need. See the [standard workflow](docs/workflow/ruby_gem.md) and [Detailed Usage](docs/usage.md) for examples.

- **Project conventions:** choose [version objects](docs/usage.md#version-objects) and [changelog formats](docs/usage.md#changelog-objects), or write your own.
- **Extra steps:** add [lifecycle hooks](docs/workflow/hooks.md) for checks, file edits, publication observers, and notifications without replacing the pipeline.
- **Custom callbacks:** replace [validation, preparation, publication, and notifications](docs/tasks.md). Callbacks receive an [execution context](docs/execution_context.md) with release data, step history, and the workflow.
- **Semantic releases:** opt into [Conventional Commits, versions from release history, and generated notes](docs/workflow/semantic_ruby_gem.md).
- **Packages and registries:** override [how the gem is built](docs/package/ruby_gem.md) or [where it is published](docs/destination.md).
- **Release hosting:** replace or turn off [GitHub Release creation](docs/workflow/ruby_gem.md#hosting) without affecting gem publication or Git.
- **CI platforms:** choose the platform, registry, and hosting independently. Supply an [execution provider](docs/execution_provider.md) for environment variables, metadata, temporary storage, and authentication. GitHub Actions is the only built-in platform; others need their own adapter and pipeline.
- **Actions options:** override commands, inputs, and timezone through the [Actions Reference](docs/actions/release.md), or use the [Composite Action](docs/actions/action.md) as a step in your own job.
- **Testing:** use optional [RSpec helpers and local publishing stand-ins](docs/testing.md) to test your release customizations and the files they change.

For complete examples, see [releasing ruby-gem-release itself](examples/self_release/README.md) and [GitLab and semantic releases](examples/gitlab_semantic_release/README.md).

The defaults include [clean-checkout checks](docs/source_control/git.md), [duplicate-version checks](docs/destination/ruby_gems.md#check-version), and [preserved recovery artifacts](docs/actions/release.md#recovery-artifacts). Custom publication callbacks must keep the documented order and artifact checks.

## Upgrading

See [UPGRADING.md](UPGRADING.md) for breaking changes and migration steps. Upgrade the gem and pinned workflow or action together.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), [DESIGN.md](DESIGN.md), [CHANGELOG.md](CHANGELOG.md), and [RELEASING.md](RELEASING.md).

## License

Distributed under the [MIT License](LICENSE.txt).
