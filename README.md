<img src="assets/logo.png" alt="A ruby gemstone launching like a rocket" width="160">

# Ruby Gem Release

[![Test](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml/badge.svg)](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml) [![Coverage Status](https://coveralls.io/repos/github/dblock/ruby-gem-release/badge.svg?branch=master)](https://coveralls.io/github/dblock/ruby-gem-release?branch=master)

**Release your Ruby gem from GitHub Actions—without maintaining custom release scripts or storing a RubyGems API key.**

Update your changelog, validate and publish your gem, create its GitHub Release, and prepare the next development version with one workflow dispatch. Choose your version and changelog formats; the standard workflow handles the release sequence.

- **No stored RubyGems API key:** Authenticate with RubyGems Trusted Publishing using OpenID Connect (OIDC).
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

permissions:
  contents: write
  id-token: write

jobs:
  release:
    uses: dblock/ruby-gem-release/.github/workflows/release.yml@master
    with:
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

Your branch rules must permit release commits and tags to be pushed; see [branch permissions](RELEASING.md#one-time-setup). Review the changes and dispatch the workflow from your default branch:

```sh
gh workflow run release.yml
```

## Configuration

See [Detailed Usage](docs/usage.md#configuration) for workflow customization, callbacks, and available classes, and the [Actions Reference](docs/actions/release.md) for inputs and defaults.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), [DESIGN.md](DESIGN.md), [CHANGELOG.md](CHANGELOG.md), and [RELEASING.md](RELEASING.md).

## License

Distributed under the [MIT License](LICENSE.txt).
