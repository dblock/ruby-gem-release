# GitLab and Semantic Releases

This example shows a complete configuration of independent customization points: GitLab execution, commit-driven version selection, generated release notes, and GitLab hosted releases. It keeps the standard Ruby gem builder, RubyGems destination, version-file editor, Git implementation, and publication order.

**This is an architectural scaffold, not a working GitLab integration or semantic-release implementation.** The [execution provider](gitlab.rb), [hosted-release provider](gitlab_release.rb), [semantic decision](semantic_release.rb), and [generated changelog](semantic_changelog.rb) are example-local placeholders that raise `NotImplementedError` for missing operations. They are not built-in providers and are not installed with the gem. No GitLab pipeline is supplied. The missing semantic-release capabilities are tracked in [#34](https://github.com/dblock/ruby-gem-release/issues/34).

Start with [the self-release walkthrough](../self_release/README.md) for small customizations that work today.

## 1. Compose the Workflow

Copy the example [Rakefile](Rakefile) and its four Ruby files into your project, adjust the version path, and implement the placeholders before attempting a release:

```ruby
require 'ruby-gem-release/workflow/ruby_gem'
require_relative 'gitlab'
require_relative 'gitlab_release'
require_relative 'semantic_release'
require_relative 'semantic_changelog'

decision = GitLabSemanticReleaseExample::SemanticRelease.new

RubyGemRelease::Workflow::RubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
  changelog: GitLabSemanticReleaseExample::SemanticChangelog.new,
  provider: GitLabSemanticReleaseExample::GitLab.new,
  hosting: GitLabSemanticReleaseExample::GitLabRelease.new,
  validate: decision.method(:proceed?)
).install_tasks
```

Install this workflow only once; do not also install the default workflow or another `Tasks` configuration. The configuration registers tasks without contacting GitLab or publishing a package. Calling a missing provider operation fails explicitly rather than silently falling back to GitHub.

The default `Destination::RubyGems` still checks and publishes to RubyGems. Replacing the execution provider does not select a GitLab package registry, and replacing hosted releases does not replace Git.

## 2. Implement GitLab Execution

The `GitLab` placeholder subclasses [`ExecutionProvider`](../../docs/execution_provider.md). Implement its methods to transport environment exports and outputs, map branch metadata to a full `refs/heads/...` ref, supply execution snapshots and phase identities, report failures, and acquire and safely handle identity tokens.

Keep exports available through `fetch` in the current process as well as subsequent processes. This is especially important for `INPUT_VERSION`, which validation sets before preparation. The base provider's in-memory environment updates alone do not provide transport between jobs or Ruby processes.

Before constructing the workflow, configure `DEFAULT_BRANCH`, `INPUT_GEMSPEC`, `INPUT_VERSION` (empty for automatic selection), and `TZ`. Set `RELEASE_DIRECTORY` to a private directory outside the checkout; keep it and the exported `RELEASE_STATE` available through every release phase, including failure handling. The inherited neutral Git identity can be overridden with `GIT_USER_NAME` and `GIT_USER_EMAIL`. Add GitLab-specific context metadata without putting platform clients into immutable execution snapshots.

The pipeline owns a complete checkout and release history, dependencies, tests, authorized default-branch execution, concurrency, protected credentials, conditional phases, and recovery-artifact uploads. The GitHub reusable workflow and composite action are not portable GitLab pipelines.

## 3. Implement Semantic Release Decisions

`SemanticRelease#version_for(ctx)` is the placeholder for release-history discovery, Conventional Commits analysis, semantic version calculation, and note generation. Its contract is:

- Return a numeric `MAJOR.MINOR.PATCH` string when a release is needed, or `nil` for a successful skip.
- Calculate from the last released version and commits since that release, not `ctx.release.previous_version`, which is the checked-in development version.
- Define first-release behavior, tag conventions, and the precedence of any explicitly supplied version.
- Analyze once and persist an immutable decision containing the selected version, generated notes, and analyzed commit range for later processes.

The implemented `proceed?(ctx)` wrapper converts `nil` to `false` and a selected version to `true`, exporting the validated selection as `INPUT_VERSION`. The standard prepare callback then calls `Version::RubyConstant#set!` inside its trusted staging boundary. Prepared-version resolution verifies that the gemspec matches the selection and checks the destination for duplicate versions.

The custom validation callback replaces the default handwritten-changelog check. A no-release decision must stop downstream phases successfully, not produce an empty release or call result callbacks.

Do not store the decision only in an instance variable: the Rakefile and providers are recreated in each Ruby process. The library's versioned `Workflow::State` currently supports next-version callback data, not arbitrary semantic decisions. Implement separate private decision storage outside the checkout, transport its location through the provider, and bind the loaded decision to the captured commit and selected release version.

## 4. Implement Generated Notes and Hosting

`SemanticChangelog#release!(release)` should load the persisted decision, verify its version, and write its generated notes to `CHANGELOG.md`. It runs inside the standard preparation boundary, so generated notes are staged with the selected version. Implement `prepare_next!(release)` for the chosen changelog convention as well; do not reanalyze commits during preparation.

`GitLabRelease#publish!(release, package:)` replaces only hosted-release creation. Load the same decision's notes and use `package.artifact(release)` to obtain the verified archive. Create the hosted release only after the release commit and tag have been pushed. Avoid rebuilding or selecting an arbitrary gem file.

The standard publication callback still checks the registry, commits, builds once, tags locally, uploads the exact gem, pushes the commit and tag atomically, and finally invokes GitLab hosting. Registry failure must prevent the push and hosted release; publication failures must retain recovery files.

This configuration deliberately retains the standard patch increment and next-development commit after publication. Semantic decisions must therefore use release history rather than that incremented version. A workflow that omits development bumps needs a custom [`Tasks.install`](../../docs/tasks.md) sequence instead; this example does not add a new bump policy.

## 5. Supply the Pipeline and Authentication

An implemented GitLab pipeline must invoke context capture, validation, preparation, prepared-version resolution, project tests, destination authentication, publication, next-development preparation, and success handling in that order. Read the transported `proceed` output after validation and stop successfully when it is `false`. On failure, identify the failed phase and invoke failure handling; preserve the gem, digest manifest, and recovery bundle even if publication fails.

RubyGems remains an independent integration. Implement compatible identity-token acquisition and configure a RubyGems trusted publisher supported by the actual platform, or supply appropriately protected preconfigured credentials and an explicit destination authentication policy. The GitHub credentials action cannot authenticate a GitLab job. Neither this scaffold nor a GitLab identity token alone establishes registry trust.

Before enabling real publication, test the completed adapters across separate processes using local Git remotes and isolated registry and hosting boundaries, following the [provider-neutral consumer tests](../../spec/integration/workflow_portable_release_spec.rb). Verify successful skipping, selected versions, generated notes, exact-artifact publication, recovery, and failure callbacks without contacting production services.
