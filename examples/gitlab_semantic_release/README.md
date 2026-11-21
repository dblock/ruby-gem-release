# GitLab and Semantic Releases

This example combines the built-in [semantic workflow](../../docs/workflow/semantic_ruby_gem.md) with custom GitLab execution and hosting. It keeps the standard gem builder, RubyGems destination, version file editor, Git support, and publication order.

**The GitLab parts are a scaffold, not a working integration.** The example [execution provider](gitlab.rb) and [hosting provider](gitlab_release.rb) raise `NotImplementedError` for missing operations, and there is no GitLab pipeline. Commit analysis, version selection, generated notes, and saving the decision are real; the gem implements them.

For smaller customizations, start with [the self-release walkthrough](../self_release/README.md). You can also try the semantic workflow with the default GitHub provider before writing GitLab adapters.

## 1. Compose the Workflow

Copy the [Rakefile](Rakefile), `gitlab.rb`, and `gitlab_release.rb` into your project and set your version path:

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

Install only this workflow, not the manual workflow or another `Tasks` setup. Loading the Rakefile neither contacts GitLab nor publishes. Missing provider operations fail; they never fall back to GitHub.

The execution platform, registry, and hosting are separate choices. This setup still publishes to RubyGems, not a GitLab registry.

## 2. Implement GitLab Execution

The `GitLab` class subclasses [`ExecutionProvider`](../../docs/execution_provider.md). Implement:

- reading inputs and exporting values, available through `fetch` in this process and in later ones
- full Git refs
- execution snapshots and step identities
- failure reporting
- identity tokens and safe secret handling

Set `DEFAULT_BRANCH`, `INPUT_GEMSPEC_PATH`, `INPUT_VERSION` (empty to select from commits), and `TZ`. Point `RELEASE_DATA_DIR` at a private directory outside the checkout. Keep that directory and the exported `RELEASE_STATE_FILE`, initial commit, initial version, and release date for the whole pipeline, including failure handling. To change the default Git identity, set `GIT_USER_NAME` and `GIT_USER_EMAIL`.

Your pipeline must provide a full checkout with tags, dependencies, tests, default-branch-only execution, concurrency control, protected credentials, conditional steps, and artifact uploads. The GitHub reusable workflow and composite action do not run on GitLab.

## 3. Use Built-in Semantic Decisions

The gem analyzes commits, selects the version, and generates notes once during validation, then exposes the decision as `ctx.analysis` in later callbacks. Do not export the version as `INPUT_VERSION` or analyze again in another process. Having no releasable commits fails validation unless you pass an explicit version. See the [semantic workflow reference](../../docs/workflow/semantic_ruby_gem.md) for version rules, first releases, custom rules, changelog options, and `bump: true`.

## 4. Implement GitLab Hosting

`GitLabRelease#publish!(release, package:)` replaces only hosting. Use `release.notes` for the body and `package.artifact(release)` for the verified gem file. Verify metadata and asset bytes; replace changed notes and assets, but fail on tag conflicts. Do not regenerate notes or rebuild the gem here.

Publication calls hosting last, after the gem is published and the commit and tag are pushed; see [Execution](../../docs/actions/release.md#execution).

## 5. Supply the Pipeline and Authentication

Run these tasks in order: capture, validate, prepare, resolve, project tests, checkpoint, artifact upload (required), publish, bump, and success. Stop on any failure, including an empty release, and run failure handling instead of the remaining steps. Every task must follow the [rerun rules](../../RELEASING.md#verify-and-recover). The bump task does nothing unless enabled.

Publication authenticates through the configured destination. For RubyGems, either implement identity-token exchange with a trusted publisher that supports your platform, or supply protected credentials with an explicit destination authentication policy. Neither this scaffold nor a GitLab identity token sets up registry trust on its own.

Before real publication, test your adapters across separate processes, with local Git remotes and isolated registry and hosting, as in the [provider-neutral consumer tests](../../spec/integration/consumer/portable_release_spec.rb). Check empty-release rejection, selected versions, generated notes, exact-artifact publication, reruns, and failure callbacks without contacting production services.
