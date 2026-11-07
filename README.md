# Ruby Gem Release with OIDC

[![test](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml/badge.svg)](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml) [![Coverage Status](https://coveralls.io/repos/github/dblock/ruby-gem-release/badge.svg?branch=master)](https://coveralls.io/github/dblock/ruby-gem-release?branch=master)

Reusable GitHub Actions workflow and Ruby Rake tasks for releasing Ruby gems.

## Usage

### 1. Install the Tasks

For a version file such as `lib/example/version.rb`:

```ruby
# frozen_string_literal: true

module Example
  VERSION = '0.1.0'
end
```

Add `ruby-gem-release` to the development dependencies and install its tasks in the project's Rakefile, replacing `lib/example/version.rb` with the path to your version file:

```ruby
require 'ruby-gem-release/tasks'

RubyGemRelease::Tasks.install(version_file: 'lib/example/version.rb', version_constant: 'VERSION')
```

### 2. Add the Release Workflow

Add `.github/workflows/release.yml` using the [sample workflow](examples/.github/workflows/release.yml), replacing the gem specification path and Ruby version with your project's values:

```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      version:
        description: Release version
        required: true
        type: string

permissions:
  contents: write
  id-token: write

jobs:
  release:
    uses: dblock/ruby-gem-release/.github/workflows/release.yml@master
    with:
      version: ${{ inputs.version }}
      gemspec: example.gemspec
      ruby-version: '3.3'
```

### 3. Configure Trusted Publishing

In your GitHub repository, open **Settings → Environments** and create an environment named `release`. Alternatively, from your repository directory, use `gh`:

```sh
gh api --method PUT repos/{owner}/{repo}/environments/release
```

On [RubyGems.org](https://rubygems.org), open your gem's **Trusted publishers** page and create a [trusted publisher](https://guides.rubygems.org/trusted-publishing/#using-reusable-workflows). Set the repository fields to your gem's repository, the workflow filename to `release.yml`, and the environment to `release`. Set the separate workflow repository fields to `dblock` and `ruby-gem-release`; these identify the reusable workflow RubyGems verifies in the OIDC token. For a new gem, use the [pending trusted publishers page](https://rubygems.org/profile/oidc/pending_trusted_publishers) instead.

## GitHub Branch Protection and Rulesets

In **Settings → Environments → release**, restrict deployment branches to your default branch and add required reviewers if available. The workflow also rejects non-default-branch releases.

Check **Settings → Branches** for branch protection rules and **Settings → Rules → Rulesets** for rulesets affecting the default branch. The workflow must be able to push release commits and a tag: a rule requiring pull requests or restricting pushes can block the Actions token unless a suitable bypass is configured. Keep force-push and deletion restrictions in place. If you remove a pull-request requirement instead, direct pushes become possible for other permitted writers too. See [RELEASING.md](RELEASING.md) for details.

## Workflow Commands

By default, the workflow sets the configured version to `RELEASE_VERSION`, runs `bundle exec rake`, and bumps the patch version after publication. Override the `prepare`, `validate`, or `bump` inputs with project-specific shell commands when needed; for example, `prepare` can also update the changelog. Pin the workflow to a reviewed release or commit instead of `master` when available. See [RELEASING.md](RELEASING.md) for required permissions, trusted-publisher configuration, failure recovery, and a dry run.

## Version Tasks

The version file must contain exactly one assignment to the named constant. Versions must be numeric `MAJOR.MINOR.PATCH`.

- `bundle exec rake ruby_gem_release:version:read` prints the current version.
- `bundle exec rake 'ruby_gem_release:version:set[1.2.3]'` sets the version.
- `bundle exec rake 'ruby_gem_release:version:bump[minor]'` increments `major`, `minor`, or `patch`, resetting lower components. The default is `patch`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), [DESIGN.md](DESIGN.md), [CHANGELOG.md](CHANGELOG.md), and [RELEASING.md](RELEASING.md).

## License

Distributed under the [MIT License](LICENSE.txt).
