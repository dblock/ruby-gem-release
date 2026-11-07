<img src="assets/logo.png" alt="A ruby gemstone launching like a rocket" width="160">

# Ruby Gem Release with OIDC

[![Test](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml/badge.svg)](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml) [![Coverage Status](https://coveralls.io/repos/github/dblock/ruby-gem-release/badge.svg?branch=master)](https://coveralls.io/github/dblock/ruby-gem-release?branch=master)

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

And a changelog such as [this Keep a Changelog example](examples/keep_a_changelog/CHANGELOG.md).

Add `ruby-gem-release` to the development dependencies and install its tasks in the project's Rakefile, replacing `lib/example/version.rb` with the path to your version file:

```ruby
require 'ruby-gem-release/tasks'
require 'ruby-gem-release/changelog'
require 'ruby-gem-release/hosting/github_release'
require 'ruby-gem-release/package/ruby_gem'
require 'ruby-gem-release/source_control/git'

RubyGemRelease::Tasks.install do |tasks|
  version = RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION')
  changelog = RubyGemRelease::Changelog::KeepAChangelog.new(path: 'CHANGELOG.md')
  package = RubyGemRelease::Package::RubyGem.new(gemspec: 'example.gemspec')
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

### 3. Configure Trusted Publishing

In your GitHub repository, open **Settings → Environments** and create an environment named `release`. Alternatively, from your repository directory, use `gh`:

```sh
gh api --method PUT repos/{owner}/{repo}/environments/release
```

On [RubyGems.org](https://rubygems.org), open your gem's **Trusted publishers** page and create a [trusted publisher](https://guides.rubygems.org/trusted-publishing/#using-reusable-workflows). Set the repository fields to your gem's repository, the workflow filename to `release.yml`, and the environment to `release`. Set the separate workflow repository fields to `dblock` and `ruby-gem-release`; these identify the reusable workflow RubyGems verifies in the OIDC token. For a new gem, use the [pending trusted publishers page](https://rubygems.org/profile/oidc/pending_trusted_publishers) instead.

For example, the trusted publishers page for a gem named `example` is `https://rubygems.org/gems/example/trusted_publishers`.

### 4. Make a Release

From your default branch, review the changes and dispatch the workflow:

```sh
gh workflow run release.yml
```

## GitHub Branch Protection and Rulesets

In **Settings → Environments → release**, restrict deployment branches to your default branch and add required reviewers if available. The workflow also rejects non-default-branch releases.

If the environment requires approval, a designated reviewer must open the run under **Actions** in GitHub and select **Review deployments**.

Check **Settings → Branches** for branch protection rules and **Settings → Rules → Rulesets** for rulesets affecting the default branch. The workflow must be able to push release commits and a tag: a rule requiring pull requests or restricting pushes can block the Actions token unless a suitable bypass is configured. Keep force-push and deletion restrictions in place. If you remove a pull-request requirement instead, direct pushes become possible for other permitted writers too. See [RELEASING.md](RELEASING.md) for details.

## Workflow Commands

The workflow runs on the default branch; [`Workflow`](docs/workflow.md) reads the current version from the gemspec before preparation, then resolves the version to publish from the prepared gemspec. Pass `-f version=0.1.0` to `gh workflow run` to require that prepared version; the input does not set the version, and a mismatch fails before publication. It uses the only gem specification in the repository root; set the `gemspec` input to a path if there are none or multiple.

By default, it runs the before-release callback, `bundle exec rake`, the publication callback, and the next-version callback. Version changes, commits, tags, builds, and publication are explicit callback operations. Override the `prepare`, `validate`, `publish`, or `bump` inputs with trusted shell commands when needed. The `publish` input replaces the former `github-release` input because this callback now owns the entire publication sequence. Check the workflow run and verify the published gem and release; see [RELEASING.md](RELEASING.md) for recovery instructions. Pin the workflow to a reviewed release or commit instead of `master` when available.

## Version Objects

[`RubyConstant`](docs/version/ruby_constant.md) reads and updates numeric versions without evaluating the version file. Version objects are local to your callbacks; use your own objects for other file formats.

## Release Callbacks

[`Tasks`](docs/tasks.md) registers `before_release`, `publish`, and `after_release` callbacks receiving an immutable [`Release`](docs/release.md) context. Unregistered callbacks do nothing; exceptions fail the task. All callbacks run in dry-run mode. The supplied classes skip remote writes, but custom callback code must be safe and trusted.

## Changelog Objects

[`KeepAChangelog`](docs/changelog/keep_a_changelog.md) updates Unreleased sections and comparison references. [`Intridea`](docs/changelog/intridea.md) updates Next sections with a configured contribution placeholder. Both inherit source-preserving behavior from [`Base`](docs/changelog/base.md) and own their file updates. Use custom callbacks for other formats.

## GitHub Releases

[`GitHubRelease`](docs/hosting/github_release.md) creates a release with generated notes and the exact published gem attached. Invoke it after `git.push!` in `tasks.publish`; omit only `github.publish!` to disable GitHub Release creation without disabling package publication.

## Packages and Git

[`Package::RubyGem`](docs/package/ruby_gem.md) builds once, verifies the exact artifact, and publishes it to RubyGems. [`SourceControl::Git`](docs/source_control/git.md) commits release files, tags the release, preserves a recovery bundle, checks branch concurrency, and pushes atomically. [`Hosting::GitHubRelease`](docs/hosting/github_release.md) owns hosting-specific publication. File paths mirror these namespaces; operations and callback ordering are unchanged. Both package and Git objects perform local work in dry runs without publishing or pushing.

## Git Commit Identity

Set the reusable workflow's `git-user-name` and `git-user-email` inputs to customize both release and next-version commit attribution. Defaults are `github-actions[bot]` and `github-actions[bot]@users.noreply.github.com`. Values must be nonempty and contain no line breaks. Configuration applies only to the checkout and does not change authentication or push permissions.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md), [DESIGN.md](DESIGN.md), [CHANGELOG.md](CHANGELOG.md), and [RELEASING.md](RELEASING.md).

## License

Distributed under the [MIT License](LICENSE.txt).
