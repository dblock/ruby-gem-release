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
      # Write the gemspec, version, changelog, README, and test Rakefile here.
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

Copy real project files instead of duplicating their contents in the spec:

```ruby
project.copy_files(path: File.expand_path('..', __dir__))
```

`path:` is the source directory. By default, `copy_files` copies all files recursively, including hidden files, but skips `.git` metadata to preserve the fixture's isolated repository. Pass `files: %w[README.md tasks/release_notes.rb]` to copy only selected relative files, or `files: []` to copy nothing.

Copying preserves relative paths and file modes. Missing files, directory entries, absolute paths, Git metadata, and paths or symbolic links that escape either root are rejected. All selected files are checked before copying.

`release!` runs capture, validation, preparation, resolution, checkpoint, publication, development bump, and success in separate Rake processes. Pass `test_task: 'verify_release'` to run a fixture-specific check after resolution; the default skips the project's test suite to avoid recursively running this spec. Use `run_task('release:prepare')` for individual tasks and `git(...)` or `remote_file(ref, path)` to inspect results.

The child processes retain Ruby/Bundler paths but do not inherit Actions variables, credentials, Git overrides, or outer release state. `project.environment` lets you add explicit fixture inputs. The helper uses the currently loaded release gem and parent bundle.

## Local Publication

Keep the project's real version object, changelog, and hooks. In the fixture Rakefile, pass these test-only overrides to its workflow builder:

```ruby
require 'ruby-gem-release/rspec'

ProjectReleaseWorkflow.build(
  provider: RubyGemRelease::RSpec::Provider.new,
  destination: RubyGemRelease::RSpec::Destination.new,
  hosting: RubyGemRelease::RSpec::Hosting.new
).install_tasks
```

The provider transports exported values and failed-task information between fixture processes. The destination and hosting adapters copy the exact built archive to `registry/VERSION.gem` and `hosting/VERSION.gem` under `RELEASE_DATA_DIR`, without authentication or network publication. Repetition accepts identical archives and rejects checksum conflicts. Set `failure: 'Publication rejected'` on either adapter to exercise a failure.

These are explicit replacements, not a sandbox: custom callbacks can still make external calls. Keep all Git remotes local, replace every external publication boundary, and never dispatch a publishing Actions workflow from these specs.

## Check Project-Specific Behavior

Test the behavior your project added, not only that release tasks are registered. Assert the exact README content in both the release tag and the next development commit. This catches a later change that removes the README update even though the gem's standard release still succeeds.

Also cover failures and reruns where they matter to the customization: assert that rejected publication leaves the remote release ref unchanged, expected recovery artifacts remain available, and repeating a successful operation does not move immutable release tags or change already-prepared files.

The [self-release example](../examples/self_release/README.md) also has a [focused version spec](../spec/release_version_spec.rb) covering README and documentation pins. The [portable integration specs](../spec/integration/workflow_portable_release_spec.rb) reuse the helper for more extensive cross-process and failure coverage.
