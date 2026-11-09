<img src="assets/logo.png" alt="A ruby gemstone launching like a rocket" width="160">

# Ruby Gem Release

[![Gem Version](https://img.shields.io/gem/v/ruby-gem-release.svg)](https://rubygems.org/gems/ruby-gem-release) [![Test](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml/badge.svg)](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml) [![Coverage Status](https://coveralls.io/repos/github/dblock/ruby-gem-release/badge.svg?branch=master)](https://coveralls.io/github/dblock/ruby-gem-release?branch=master)

**Release your Ruby gem from GitHub Actions without maintaining custom release scripts or storing a RubyGems API key.**

Update your changelog, validate and publish your gem, create its GitHub Release, and prepare the next development iteration with one workflow dispatch. Choose your version and changelog formats; the standard workflow handles the release sequence.

The default setup below requires Ruby 3.3+, GitHub Actions, and RubyGems Trusted Publishing.

## Usage

### 1. Configure Your Gem

Add `ruby-gem-release` to the development dependencies and install the standard workflow in your Rakefile. Choose your version file and changelog format explicitly:

```ruby
require 'ruby-gem-release/workflow/ruby_gem'
require 'ruby-gem-release/changelog'

RubyGemRelease::Workflow::RubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
  changelog: RubyGemRelease::Changelog::KeepAChangelog.new
).install_tasks
```

These defaults select the gemspec and repository, skip empty pending notes, prepare the changelog, publish to RubyGems and GitHub Releases, and increment the patch version for the next development iteration. Dates use UTC.

### 2. Add the Release Workflow

Add `.github/workflows/release.yml` using the [sample workflow](examples/.github/workflows/release.yml), replacing the Ruby version with your project's value:

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
    uses: dblock/ruby-gem-release/.github/workflows/release.yml@v0.4.0
    with:
      ruby-version: '3.3'
      version: ${{ inputs.version }}
      rubygems-owner: ${{ inputs.rubygems-owner }}
```

### 3. Enable Trusted Publishing

In your GitHub repository, open **Settings → Environments** and create an environment named `release`. Alternatively, from your repository directory, use `gh`:

```sh
gh api --method PUT repos/{owner}/{repo}/environments/release
```

For a new gem, open the [pending trusted publishers page](https://rubygems.org/profile/oidc/pending_trusted_publishers). For an existing gem, open your existing gem's **Trusted publishers** page (e.g. `https://rubygems.org/gems/example/trusted_publishers`). Create a [trusted publisher](https://guides.rubygems.org/trusted-publishing/#using-reusable-workflows). Set the repository fields to your gem's repository, the workflow filename to `release.yml`, and the environment to `release`. Set the separate workflow repository fields to `dblock` and `ruby-gem-release`; these identify the reusable workflow RubyGems verifies in the OIDC token.

Collaborators with write access can dispatch releases after this setup, without repository admin access or their own RubyGems credentials. Creating the environment alone does not restrict publication. Configure [required maintainer approval and deployment branches](RELEASING.md#maintainer-approved-publication) to control who approves publication.

### 4. Make a Release

Your branch rules must permit release commits and tags to be pushed; see [branch permissions](RELEASING.md#one-time-setup). Dispatching starts a publishing run; when required reviewers are configured, the release job waits for approval from a designated maintainer. Run your project's tests and build checks, review the changes, and dispatch from your default branch:

**First release:** Pass the numeric RubyGems account ID shown on the Pending Trusted Publishers page as `rubygems-owner`. This declares the account that will own the gem on its first publication. Replace `YOUR_ACCOUNT_ID` below with that ID:

```sh
gh workflow run release.yml -f rubygems-owner=YOUR_ACCOUNT_ID
```

**Subsequent releases:** Omit `rubygems-owner` once the gem exists. Its trusted publisher is still required, but the account ID is no longer needed:

```sh
gh workflow run release.yml
```

To release a different version, select it in the dispatch form or pass `-f version=1.2.3`. The standard workflow updates the configured version file before preparing the changelog, then starts the next development iteration from the selected release version.

For a real-world example of adding release automation to an existing gem, see [ruby-link-checker #26](https://github.com/dblock/ruby-link-checker/pull/26). It adds the dependency, Rake tasks, reusable workflow, and release instructions while preserving the existing changelog format.

## Extending the Workflow

Start with the defaults above and replace only the parts your project needs. The [standard workflow](docs/workflow/ruby_gem.md) keeps the release sequence intact while accepting custom components; [Detailed Usage](docs/usage.md) shows file examples and a complete manual callback configuration.

- **Project conventions:** Choose [version objects](docs/usage.md#version-objects) and [changelog formats](docs/usage.md#changelog-objects), including custom implementations.
- **Release decisions and callbacks:** Customize [validation, preparation, publication, and notifications](docs/tasks.md). Callbacks receive an [execution context](docs/execution_context.md) with release data, step history, and the configured workflow.
- **Packages and registries:** Override [package construction](docs/package/ruby_gem.md) or supply a [registry destination](docs/destination.md) independently of hosted releases.
- **Release hosting:** Replace or disable [GitHub Release creation](docs/workflow/ruby_gem.md#hosting) without changing package publication or Git operations.
- **Execution platforms:** Supply an [execution provider](docs/execution_provider.md) for environment transport, metadata, temporary storage, and authentication services. GitHub Actions is the only built-in external platform; another platform needs its own adapter and pipeline.
- **Actions integration:** Override commands, inputs, and timezone through the [Actions Reference](docs/actions/release.md), or use the [Composite Action](docs/actions/action.md) inside a caller-owned job.

Execution platform, package registry, and release hosting are separate choices. Changing one does not automatically change the others.

The defaults retain [clean-checkout checks](docs/source_control/git.md), [duplicate-version checks](docs/destination/ruby_gems.md#check-version), and [verified recovery artifacts](docs/actions/release.md#recovery-artifacts). Custom publication callbacks must preserve the documented ordering and artifact checks.

## Upgrading

See [UPGRADING.md](UPGRADING.md) for breaking changes and migration steps. Upgrade the gem and pinned workflow or action together.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), [DESIGN.md](DESIGN.md), [CHANGELOG.md](CHANGELOG.md), and [RELEASING.md](RELEASING.md).

## License

Distributed under the [MIT License](LICENSE.txt).
