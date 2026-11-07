<img src="assets/logo.png" alt="A ruby gemstone launching like a rocket" width="160">

# Ruby Gem Release

[![Test](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml/badge.svg)](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml) [![Coverage Status](https://coveralls.io/repos/github/dblock/ruby-gem-release/badge.svg?branch=master)](https://coveralls.io/github/dblock/ruby-gem-release?branch=master)

**Release your Ruby gem from GitHub Actions—without maintaining custom release scripts or storing a RubyGems API key.**

Update your changelog, validate and publish your gem, create its GitHub Release, and prepare the next development version with one workflow dispatch. Choose your version and changelog formats; the standard workflow handles the release sequence.

- **No stored RubyGems API key:** Authenticate with RubyGems Trusted Publishing.
- **Try it before publishing:** Dry runs exercise local commits, builds, and tags without uploading or pushing.
- **Keep your conventions:** Use the standard workflow or compose Ruby objects and callbacks for custom releases.

Requires Ruby 3.3+, GitHub Actions, and RubyGems Trusted Publishing.

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

The standard workflow handles changelog updates, publication, and the next development version, selecting the gemspec and repository using unambiguous defaults. See [Detailed Usage](docs/usage.md) for file examples and custom release callbacks.

### 2. Add the Release Workflow

Add `.github/workflows/release.yml` using the [sample workflow](examples/.github/workflows/release.yml), replacing the Ruby version with your project's value:

```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      version:
        description: Optional expected version (must match the prepared gemspec)
        required: false
        type: string

permissions:
  contents: write
  id-token: write

jobs:
  release:
    uses: dblock/ruby-gem-release/.github/workflows/release.yml@master
    with:
      version: ${{ inputs.version }}
      ruby-version: '3.3'
```

### 3. Enable Trusted Publishing

In your GitHub repository, open **Settings → Environments** and create an environment named `release`. Alternatively, from your repository directory, use `gh`:

```sh
gh api --method PUT repos/{owner}/{repo}/environments/release
```

On [RubyGems.org](https://rubygems.org), open your gem's **Trusted publishers** page and create a [trusted publisher](https://guides.rubygems.org/trusted-publishing/#using-reusable-workflows). Set the repository fields to your gem's repository, the workflow filename to `release.yml`, and the environment to `release`. Set the separate workflow repository fields to `dblock` and `ruby-gem-release`; these identify the reusable workflow RubyGems verifies in the OIDC token. For a new gem, use the [pending trusted publishers page](https://rubygems.org/profile/oidc/pending_trusted_publishers) instead.

For example, the trusted publishers page for a gem named `example` is `https://rubygems.org/gems/example/trusted_publishers`.

### 4. Make a Release

Check [branch permissions](#github-branch-protection-and-rulesets), then review the changes and dispatch the workflow from your default branch:

```sh
gh workflow run release.yml
```

## Configuration

### GitHub Branch Protection and Rulesets

In **Settings → Environments → release**, restrict deployment branches to your default branch and add required reviewers if available. The workflow also rejects non-default-branch releases.

If the environment requires approval, a designated reviewer must open the run under **Actions** in GitHub and select **Review deployments**.

Check **Settings → Branches** for branch protection rules and **Settings → Rules → Rulesets** for rulesets affecting the default branch. The workflow must be able to push release commits and a tag: a rule requiring pull requests or restricting pushes can block the Actions token unless a suitable bypass is configured. Keep force-push and deletion restrictions in place. If you remove a pull-request requirement instead, direct pushes become possible for other permitted writers too. See [RELEASING.md](RELEASING.md) for details.

### GitHub Actions Workflow

The reusable workflow provides the GitHub Actions environment for release callbacks, including setup, validation, authentication, and artifact preservation. Use its `with:` inputs to choose the gemspec, expected version, Ruby version, commands, and commit identity. Pin the workflow to a reviewed release or commit instead of `master` when available.

- [Release Workflow](docs/actions/release.md): All inputs, defaults, permissions, commands, dry runs, and recovery artifacts.
- [`Workflow::Context`](docs/workflow/context.md): Ruby context capture and prepared-version checks used by the action workflow.

### Standard Workflows

Standard workflows wire the usual release sequence using your explicitly chosen version and changelog objects. Override package, Git, or hosting objects when needed; use custom callbacks for a different sequence.

- [`Workflow::RubyGem`](docs/workflow/ruby_gem.md): Gem release preparation, publication, and next-version callbacks with conservative defaults.

### Version Objects

Version objects read, set, and increment the version stored in project files. Construct them locally in your callbacks; use your own objects for other file formats.

- [`Version::RubyConstant`](docs/version/ruby_constant.md): Numeric Ruby constant versions, updated without evaluating the file.

### Release Callbacks

Callbacks define project-specific preparation, publication, and next-version work. The standard workflow installs them for you; [Detailed Usage](docs/usage.md#custom-callbacks) shows manual configuration. Unregistered callbacks do nothing; exceptions fail the task. All callbacks run in dry-run mode. The supplied classes skip remote writes, but custom callback code must be safe and trusted.

- [`Tasks`](docs/tasks.md): Registers `before_release`, `publish`, and `after_release` callbacks and their Rake tasks.
- [`Release`](docs/release.md): Immutable version, date, and dry-run context passed to callbacks.

### Changelog Objects

Changelog objects prepare release headings and open the next development section while preserving unrelated Markdown. Choose the strategy matching your changelog format or use custom callbacks for other formats.

- [`Changelog::KeepAChangelog`](docs/changelog/keep_a_changelog.md): Unreleased sections and version comparison references.
- [`Changelog::Intridea`](docs/changelog/intridea.md): Next sections and a configured contribution placeholder.
- [`Changelog::Base`](docs/changelog/base.md): Shared source-preserving implementation for concrete strategies.

### Package Objects

Package objects build, verify, and publish the exact release artifact. They perform local builds in dry runs without uploading.

- [`Package::RubyGem`](docs/package/ruby_gem.md): Gem construction, artifact verification, and RubyGems publication.

### Source Control Objects

Source control objects manage release history independently of the repository's hosting provider. They perform local commits and tags in dry runs without pushing.

- [`SourceControl::Git`](docs/source_control/git.md): Release and next-version commits, tags, recovery bundles, branch checks, and atomic release pushes.

### Hosting Objects

Hosting objects publish release notes and attach package artifacts after the release tag is pushed. Set `hosting: nil` in the standard workflow, or omit the hosting publication call in custom callbacks, to disable hosted releases without disabling package publication.

- [`Hosting::GitHubRelease`](docs/hosting/github_release.md): GitHub Releases with generated notes and the exact gem attached.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), [DESIGN.md](DESIGN.md), [CHANGELOG.md](CHANGELOG.md), and [RELEASING.md](RELEASING.md).

## License

Distributed under the [MIT License](LICENSE.txt).
