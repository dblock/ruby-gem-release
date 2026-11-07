# Ruby Gem Release

[![test](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml/badge.svg)](https://github.com/dblock/ruby-gem-release/actions/workflows/test.yml) [![Coverage Status](https://coveralls.io/repos/github/dblock/ruby-gem-release/badge.svg?branch=master)](https://coveralls.io/github/dblock/ruby-gem-release?branch=master)

Reusable GitHub Actions workflow and Ruby Rake tasks for releasing Ruby gems.

Add `ruby-gem-release` to the development dependencies and install its tasks in the project's Rakefile:

```ruby
require 'ruby-gem-release/tasks'

RubyGemRelease::Tasks.install(version_file: 'lib/example/version.rb', version_constant: 'VERSION')
```

Run `bundle exec rake ruby_gem_release:version:read`, `bundle exec rake 'ruby_gem_release:version:set[1.2.3]'`, or `bundle exec rake 'ruby_gem_release:version:bump[minor]'`. Bump accepts `major`, `minor`, and `patch` (the default); versions must be numeric `MAJOR.MINOR.PATCH`. The file must contain exactly one assignment to the named constant.

Call the reusable workflow from a `workflow_dispatch` workflow in the publishing repository:

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
      prepare: bundle exec rake "ruby_gem_release:version:set[$RELEASE_VERSION]"
      validate: bundle exec rake
      bump: bundle exec rake ruby_gem_release:version:bump
```

Replace the example commands with project-specific preparation and validation, including changelog updates where needed. Pin the workflow to a reviewed release or commit instead of `master` when available. See [RELEASING.md](RELEASING.md) for required permissions, trusted-publisher configuration, failure recovery, and a dry run.

See [CONTRIBUTING.md](CONTRIBUTING.md), [DESIGN.md](DESIGN.md), [CHANGELOG.md](CHANGELOG.md), and [RELEASING.md](RELEASING.md).
