# Ruby Gem Release with OIDC

[![test](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml/badge.svg)](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml) [![Coverage Status](https://coveralls.io/repos/github/dblock/ruby-gem-release/badge.svg?branch=master)](https://coveralls.io/github/dblock/ruby-gem-release?branch=master)

Reusable GitHub Actions workflow and Ruby Rake tasks for releasing Ruby gems.

Add `ruby-gem-release` to the development dependencies and install its tasks in the project's Rakefile, replacing `lib/example/version.rb` with the path to your version file:

```ruby
require 'ruby-gem-release/tasks'

RubyGemRelease::Tasks.install(version_file: 'lib/example/version.rb', version_constant: 'VERSION')
```

Add `.github/workflows/release.yml` using the [sample workflow](examples/.github/workflows/release.yml), replacing the gem specification path and Ruby version with your project's values.

Create a `release` environment in your repository and configure a [RubyGems trusted publisher](https://guides.rubygems.org/trusted-publishing/#using-reusable-workflows): set the repository fields to your gem's repository, the workflow filename to `release.yml`, the environment to `release`, and the separate workflow repository fields to `dblock` and `ruby-gem-release`. For a new gem, create a pending trusted publisher.

The permissions above allow OIDC and GitHub releases; branch rules must also allow the workflow to push. Restrict the environment to the default branch and require approval when available.

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
