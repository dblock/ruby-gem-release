# GitLab and Semantic Releases

This example combines the built-in [semantic workflow](../../docs/workflow/semantic_ruby_gem.md) with custom GitLab execution and hosted releases. It keeps the standard Ruby gem builder, RubyGems destination, version-file editor, Git implementation, and publication order.

**GitLab remains an architectural scaffold, not a working integration.** The example-local [execution provider](gitlab.rb) and [hosted-release provider](gitlab_release.rb) raise `NotImplementedError` for missing operations. No GitLab pipeline is supplied. Commit analysis, version selection, generated notes, and decision persistence are implemented by the gem, not placeholders.

Start with [the self-release walkthrough](../self_release/README.md) for smaller customizations, or use the semantic workflow with the default GitHub provider before implementing GitLab adapters.

## 1. Compose the Workflow

Copy the [Rakefile](Rakefile), `gitlab.rb`, and `gitlab_release.rb` into your project and adjust the version path:

```ruby
require 'ruby-gem-release/workflow/semantic_ruby_gem'
require_relative 'gitlab'
require_relative 'gitlab_release'

RubyGemRelease::Workflow::SemanticRubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
  provider: GitLabSemanticReleaseExample::GitLab.new,
  hosting: GitLabSemanticReleaseExample::GitLabRelease.new
).install_tasks
```

Install this workflow only once; do not also install the manual workflow or another `Tasks` configuration. Registration does not contact GitLab or publish. Missing provider operations fail explicitly instead of falling back to GitHub.

Execution platform, package registry, and release hosting remain separate choices. This configuration still checks and publishes to RubyGems, not a GitLab registry.

## 2. Implement GitLab Execution

The `GitLab` placeholder subclasses [`ExecutionProvider`](../../docs/execution_provider.md). Implement environment transport, full Git refs, execution snapshots, phase identities, failure reporting, identity tokens, and safe secret handling. Keep exports available through `fetch` both in the current process and subsequent processes.

Configure `DEFAULT_BRANCH`, `INPUT_GEMSPEC_PATH`, `INPUT_VERSION` (empty for commit-driven selection), and `TZ`. Set `RELEASE_DATA_DIR` to a private directory outside the checkout. Preserve it and the exported `RELEASE_STATE_FILE`, initial commit, initial version, and release date throughout the pipeline, including failure handling. The inherited neutral Git identity can be overridden with `GIT_USER_NAME` and `GIT_USER_EMAIL`.

The pipeline owns a complete checkout with tags, dependencies, tests, authorized default-branch execution, concurrency, protected credentials, conditional phases, and recovery-artifact uploads. The GitHub reusable workflow and composite action are not portable GitLab pipelines.

## 3. Use Built-in Semantic Decisions

Validation discovers the highest reachable stable release tag, analyzes subsequent Conventional Commits, selects a version, and generates notes once. Its immutable decision is persisted in the private versioned state and exposed as `ctx.analysis` in later callbacks. Do not export the selection as `INPUT_VERSION` or reanalyze it in another process.

The selected version is based on the last release, not the checked-in development version. An explicit version can override analysis and force a release; otherwise, no releasable commits is a validation error. Preparation calls the version object's `set!` method and writes a generated changelog by default.

See the [semantic workflow reference](../../docs/workflow/semantic_ruby_gem.md) for first-release configuration, custom rules and providers, optional changelog updates, and `bump: true`. Development bumps are disabled by default for this workflow.

## 4. Implement GitLab Hosting

`GitLabRelease#publish!(release, package:)` replaces only hosting. Use `release.notes` for the captured body and `package.artifact(release)` for the verified archive. Verify metadata and asset bytes during publication; replace mutable notes/assets but reject immutable tag conflicts. Do not regenerate notes or rebuild inside hosting.

The standard publication callback commits, builds reproducibly, tags locally, verifies or uploads the exact gem, pushes commit and tag atomically, then invokes hosting. Registry failure prevents the push and hosted release; artifacts remain available for manual inspection.

## 5. Supply the Pipeline and Authentication

Invoke capture, validation, preparation, resolution, project tests, checkpoint, required artifact upload, publication, bump, and success in that order. Stop on any failed command, including empty-release validation, and invoke failure handling rather than downstream release operations. Every command must be idempotent using the current checkout and inputs; do not restore an older workflow's context. The bump task is a no-op unless enabled. Retain artifacts for manual inspection.

Publication authenticates through the configured destination. For RubyGems, implement compatible identity-token acquisition and configure a trusted publisher supported by the actual platform, or supply protected preconfigured credentials with an explicit destination authentication policy. Neither this scaffold nor a GitLab identity token alone establishes registry trust.

Before enabling real publication, test the completed adapters across separate processes using local Git remotes and isolated registry and hosting boundaries, following the [provider-neutral consumer tests](../../spec/integration/workflow_portable_release_spec.rb). Verify empty-release rejection, selected versions, generated notes, exact-artifact publication, reruns, and failure callbacks without contacting production services.
