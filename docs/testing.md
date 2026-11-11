# Testing Custom Workflows

Tests for a project's `ruby-gem-release` configuration should exercise the installed gem and the project's own release tasks. A focused test can verify a custom version object or callback, while a disposable consumer test can catch integration regressions across the workflow.

## Isolate the Release

Load the optional `ruby-gem-release/rspec` helper and include `RubyGemRelease::RSpec` in an example group. It does not add an RSpec runtime dependency or change production release tasks.

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

See the [complete spec](../examples/lifecycle_hooks/spec/release_spec.rb) for all fixture files. It exercises the [same workflow builder](../examples/lifecycle_hooks/release_workflow.rb) as the example's production Rakefile, so deleting a hook breaks the spec instead of leaving a separate test configuration working.

`with_release_project` creates a temporary checkout, local bare `origin`, and private artifact directory, then cleans them up even if the spec fails. `project.write(path, content)` creates files; `commit!` commits and pushes fixture edits to that local remote. No files or commits are changed in your working checkout.

`release!` runs capture, validation, preparation, resolution, checkpoint, publication, development bump, and success in separate Rake processes. Pass `test_task: 'verify_release'` to run a fixture-specific check after resolution; the default skips the project's test suite to avoid recursively running this spec. Use `run_task('release:prepare')` for individual tasks and `git(...)` or `remote_file(ref, path)` to inspect results.

The child processes retain Ruby/Bundler paths but do not inherit Actions variables, credentials, Git overrides, or outer release state. `project.environment` lets you add explicit fixture inputs. The helper uses the currently loaded release gem and parent bundle.

## Copy Fixture Files

Copy real project files instead of duplicating their contents in the spec. `path:` is the source directory; `files:` accepts a single relative path or glob, or an array mixing both:

```ruby
source_root = File.expand_path('..', __dir__)

project.copy_files(path: source_root)
project.copy_files(path: source_root, files: 'README.md')
project.copy_files(path: source_root, files: %w[README.md bin/run])
project.copy_files(path: source_root, files: [])
project.copy_files(path: source_root, files: '**/*.{js,md}')
project.copy_files(path: source_root, files: ['README.md', 'lib/**/*.rb', 'bin/*'])
```

Omitting `files:` or passing `nil` copies all files recursively. An empty array copies nothing. Existing exact paths take precedence over glob syntax, so a file named `[notes].md` is copied literally. Overlapping selectors copy each relative file only once.

Globs are matched relative to `path:`, not the current directory. Supported patterns include `*`, `?`, character classes such as `[ab]` or `[a-z]`, brace alternatives such as `*.{rb,md}`, and recursive `**/`. A leading `./` is accepted. `*` does not cross directory separators; use `**/*` for all nested files. Hidden files and hidden directories participate in matching, including with `**/*`. Git ignore rules are not applied, so select only the files needed by your fixture to avoid copying dependency directories and build outputs.

Whole-project copying and glob expansion skip `.git` files and directories at every level to preserve the fixture's isolated repository. Explicit paths or patterns containing a `.git` component are rejected. Glob expansion selects files rather than ordinary directories and never traverses symbolic-link directories. A matched symbolic link must resolve to a regular file inside the source root; its contents are copied, not the link itself.

Copying preserves relative paths, binary content, and file modes, and replaces selected destination files. Missing literal files, patterns matching no files, explicit directory entries, absolute paths, Git metadata, and paths or symbolic links that escape either root are rejected. Every selector must match at least one file. All selected sources and destinations are checked before any copying, so a bad selector or escaping destination link cannot leave a partially copied fixture. Empty directories are not copied.

## Local Publication

Keep the project's real version object, changelog, and hooks. For a project exposing `GrapeRelease.workflow` in `tasks/release.rb`, configure the fixture after copying that file and its dependencies:

```ruby
project.configure_workflow(
  require: 'tasks/release',
  builder: 'GrapeRelease.workflow'
)
```

`configure_workflow` writes only the fixture's Rakefile. It requires `ruby-gem-release/rspec`, loads the copied Ruby file, calls the builder with the existing local `Provider`, `Destination`, and `Hosting` adapters, and invokes `install_tasks`. Production configuration is unchanged; `release!` and `run_task` still execute the same release tasks in separate processes.

`require:` is a path inside the checkout, with or without `.rb`. Absolute paths, Git metadata, and paths or symbolic links escaping the checkout are rejected. The path is encoded as a Ruby string literal. `builder:` must be a constant path and method, such as `MyProject::Release.workflow`, not an arbitrary Ruby expression. Invalid arguments are rejected before replacing the Rakefile.

For custom setup or adapter options, keep using `project.write('Rakefile', ...)`. For example:

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

The provider transports exported values and failed-task information between fixture processes. The destination and hosting adapters copy the exact built archive to `registry/VERSION.gem` and `hosting/VERSION.gem` under `RELEASE_DATA_DIR`, without authentication or network publication. Repetition accepts identical archives and rejects checksum conflicts. Set `failure: 'Publication rejected'` on either adapter to exercise a failure.

These are explicit replacements, not a sandbox: custom callbacks can still make external calls. Keep all Git remotes local, replace every external publication boundary, and never dispatch a publishing Actions workflow from these specs.

## Check Project-Specific Behavior

Test the behavior your project added, not only that release tasks are registered. Assert the exact README content in both the release tag and the next development commit. This catches a later change that removes the README update even though the gem's standard release still succeeds.

Also cover failures and reruns where they matter to the customization: assert that rejected publication leaves the remote release ref unchanged, expected recovery artifacts remain available, and repeating a successful operation does not move immutable release tags or change already-prepared files.

The [self-release example](../examples/self_release/README.md) also has a [focused version spec](../spec/release_version_spec.rb) covering README and documentation pins. The [portable integration specs](../spec/integration/workflow_portable_release_spec.rb) reuse the helper for more extensive cross-process and failure coverage.
