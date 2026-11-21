# Testing Custom Workflows

Test your release setup by running your real release tasks against the installed gem. A focused spec can check one custom object or callback; a throwaway project catches problems across the whole release.

## Isolate the Release

Require the optional `ruby-gem-release/rspec` helper and include `RubyGemRelease::RSpec`. It adds no runtime dependency and does not change your release tasks.

```ruby
require 'ruby-gem-release/rspec'

RSpec.describe 'My release configuration' do
  include RubyGemRelease::RSpec

  it 'updates release documentation' do
    with_release_project do |project|
      # Copy the actual gemspec, version, changelog, README, and workflow files here.
      project.configure_workflow(require: 'release_workflow', builder: 'ProjectReleaseWorkflow.build')
      project.commit!
      project.release!(version: '0.2.0')

      expect(project.remote_file('v0.2.0', 'README.md')).to include('stable release')
      expect(project.remote_file('master', 'README.md')).to include('next release')
    end
  end
end
```

The [complete spec](../examples/lifecycle_hooks/spec/release_spec.rb) uses the [same workflow builder](../examples/lifecycle_hooks/release_workflow.rb) as the example's real Rakefile, so removing a hook breaks it.

`with_release_project` creates a temporary checkout, a local bare `origin`, and a private artifact directory, and deletes them afterwards even if the spec fails. Your own checkout is never touched.

- `project.write(path, content)` creates a file.
- `project.commit!` commits fixture changes and pushes them to the local `origin`.
- `project.release!` runs every release step, from capture to success, each in its own Rake process. It skips your test suite so the spec does not run itself; pass `test_task: 'verify_release'` to run a fixture check after resolution.
- `project.run_task('release:prepare')` runs one task.
- `project.git(...)` and `project.remote_file(ref, path)` inspect the result.

Child processes keep Ruby and Bundler paths but not Actions variables, credentials, Git overrides, or outer release state. Add inputs with `project.environment`. The helper uses the currently loaded release gem and bundle.

## Copy Fixture Files

Copy real project files instead of repeating them in the spec. `path:` is the source directory; `files:` takes a relative path, a glob, or an array of both:

```ruby
source_root = File.expand_path('..', __dir__)

project.copy_files(path: source_root)
project.copy_files(path: source_root, files: 'README.md')
project.copy_files(path: source_root, files: %w[README.md bin/run])
project.copy_files(path: source_root, files: [])
project.copy_files(path: source_root, files: '**/*.{js,md}')
project.copy_files(path: source_root, files: ['README.md', 'lib/**/*.rb', 'bin/*'])
```

- Omitting `files:` or passing `nil` copies everything; an empty array copies nothing.
- An existing exact path wins over glob syntax, so `[notes].md` is copied literally.
- Each file is copied once, even if several selectors match.
- `.git` is always skipped; paths or patterns that name it are rejected.
- Git ignore rules do not apply, so select only what you need to avoid copying dependencies and build outputs.
- Empty directories are not copied.

Globs match relative to `path:` and support `*`, `?`, `[ab]` or `[a-z]`, `*.{rb,md}`, recursive `**/`, and a leading `./`. `*` stays within one directory; use `**/*` for nested files. Hidden files match too. Globs select files, not directories, and never follow symbolic-link directories. A matched symbolic link must point to a regular file inside the source root; its contents are copied.

Copying keeps relative paths, content, and file modes, and overwrites existing destination files. These fail:

- missing files, or patterns that match nothing (every selector must match at least one file);
- directories named explicitly;
- absolute paths;
- paths or symbolic links that leave either root.

Everything is checked before copying starts, so a failure never leaves a half-copied fixture.

## Local Publication

Keep your real version object, changelog, and hooks. For a project that builds its workflow with `GrapeRelease.workflow` in `tasks/release.rb`, copy that file and its dependencies, then:

```ruby
project.configure_workflow(
  require: 'tasks/release',
  builder: 'GrapeRelease.workflow'
)
```

`configure_workflow` writes only the fixture's Rakefile. It loads your file, calls your builder with the helper's local `Provider`, `Destination`, and `Hosting` adapters, and calls `install_tasks`. `release!` and `run_task` still run the real tasks.

`require:` is a path inside the checkout, with or without `.rb`; absolute paths, Git metadata, and paths that leave the checkout are rejected. `builder:` must be a constant and method, such as `MyProject::Release.workflow`, not arbitrary Ruby. Invalid arguments fail before the Rakefile changes.

For custom setup or adapter options, write the Rakefile yourself:

```ruby
project.write('Rakefile', <<~RUBY)
  require 'ruby-gem-release/rspec'
  require_relative 'release_workflow'

  ProjectReleaseWorkflow.build(
    provider: RubyGemRelease::RSpec::Provider.new,
    destination: RubyGemRelease::RSpec::Destination.new(failure: 'Publication rejected'),
    hosting: RubyGemRelease::RSpec::Hosting.new
  ).install_tasks
RUBY
```

- `Provider` passes exported values and failed-task details between fixture processes.
- `Destination` and `Hosting` copy the exact built gem to `registry/VERSION.gem` and `hosting/VERSION.gem` under `RELEASE_DATA_DIR`, without authentication or network calls. A repeat accepts an identical gem and rejects a different checksum.
- Pass `failure: 'Publication rejected'` to either adapter to simulate a failure.

These adapters are not a sandbox; custom callbacks can still reach the network. Keep all Git remotes local, replace every external publication step, and never trigger a publishing Actions workflow from these specs.

## Check Project-Specific Behavior

Test what your project adds, not just that the tasks exist. For example, check the exact README text in both the release tag and the next development commit, which catches a change that silently drops the README update. Where relevant, also test that:

- a rejected publication leaves the remote release ref unchanged;
- recovery artifacts remain available;
- repeating a successful step does not move tags or change prepared files.

See also the [self-release example](../examples/self_release/README.md) and its [version spec](../spec/release_version_spec.rb), and the [portable integration specs](../spec/integration/consumer/portable_release_spec.rb) for broader cross-process and failure coverage.
