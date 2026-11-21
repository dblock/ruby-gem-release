# Design

`ruby-gem-release` provides a reusable GitHub Actions workflow, a composite action, and Ruby release tasks. Projects choose their version and changelog formats. Components are replaceable, but every release publishes in the same order.

## Component Boundaries

| Component                   | Responsibility                                                                 |
| ---                         | ---                                                                            |
| `Workflow::RubyGem`         | Install the manual release tasks.                                              |
| `Workflow::ReviewedRubyGem` | Publish an existing signed tag without editing or pushing Git changes.         |
| `Workflow::SemanticRubyGem` | Pick the version from commits, then publish in the same order.                 |
| `Tasks`                     | Register callbacks, build contexts, and report failures.                       |
| `ExecutionProvider`         | Pass inputs and exports between steps; supply run metadata and authentication. |
| `Workflow::Environment`     | Check the checkout and read package metadata before and after preparation.     |
| `Workflow::State`           | Store callback data in a private JSON file.                                    |
| `Package::RubyGem`          | Read metadata, build reproducibly, and verify the exact gem file.              |
| `Destination::RubyGems`     | Authenticate, check whether the version exists, and upload the verified gem.   |
| `SourceControl::Git`        | Stage edits, detect concurrent changes, commit, tag, and push.                 |
| `Hosting::GitHubRelease`    | Create the GitHub Release after the remote tag exists.                         |

Execution platform, registry, and hosting are independent choices. Built-in support covers GitHub Actions, RubyGems, and GitHub Releases. A hosting provider needs only an idempotent `publish!(release, package:)`; there is no base class. Class, documentation, and spec paths mirror namespaces.

## Lifecycle and Publication

Both interfaces run one fixed [step order](docs/actions/release.md#execution). Components and hooks can be replaced or added, but they cannot reorder the publication guards.

Registry upload and Git push cannot be atomic together. So a checkpoint saves the built gem and a Git bundle before anything is published, and publication uploads the gem before it pushes the commit and tag together. If the upload fails, nothing is pushed and no GitHub Release is created.

Release steps are idempotent instead of resuming from saved progress. Each rerun checks its own outputs, so there is no recovery state to store, restore, or trust. The rules are in [Verify and Recover](RELEASING.md#verify-and-recover).

Keep both YAML interfaces thin and consistent. The reusable workflow does not reference the composite action by a moving ref, so a pinned release never changes later. Both interfaces and this repository's workflows pin every external action and reusable workflow to a commit SHA with a version comment. Pinning a release by SHA therefore fixes every action that runs with release credentials. Dependabot proposes pin updates. Composite action callers own permissions, runner, environment protection, and concurrency. Commands run with release privileges and must be trusted.

## Preparation and Artifact Guards

What is tested is what is released. Only trusted preparation edits are staged, and publication fails on any later change to the working tree or index instead of staging it. See [Git preparation](docs/source_control/git.md#clean-checkout-and-preparation).

Lifecycle hooks add checks and project edits without replacing the release order; only preparation hooks may edit files. See the [hook guide](docs/workflow/hooks.md). Already-reviewed signed tags use the separate [reviewed workflow](docs/workflow/reviewed_ruby_gem.md), which shares the hook lifecycle but never commits, tags, pushes, or bumps.

Version and changelog objects edit source text without evaluating it, so formatting is preserved. Changelog parsing loads the optional `Commonmarker` gem, so the core gem needs no native dependencies. Malformed content fails instead of being skipped. See the [version](docs/version/ruby_constant.md), [references](docs/version/references.md), and [changelog](docs/changelog/base.md) contracts.

## Contexts and State

Each Actions step runs in a separate process, so every process rebuilds the workflow from the Rakefile. Callbacks receive a frozen context that is plain data, not a platform client, and domain operations receive only the immutable `Release`. See [execution contexts](docs/execution_context.md) and [tasks](docs/tasks.md).

Persisted state is deliberately minimal: a private file outside the checkout holds only the semantic decision and the next development version, with no format version or migrations. Corrupt state fails rather than being guessed at.

## Manual and Semantic Workflows

The [manual workflow](docs/workflow/ruby_gem.md) requires explicit version and changelog objects, so nothing about a project's conventions is guessed. [Semantic releases](docs/workflow/semantic_ruby_gem.md) are opt-in. Validation records one immutable decision from the commits since the last stable release tag, and later processes reuse it instead of reanalyzing, so every step publishes the same version and notes. Prereleases, maintenance branches, channels, other tag formats, and other platform adapters are out of scope.

## Authentication

Authentication happens inside `release:publish`, through the destination's `authenticate!(provider:)` hook, not in a YAML step. This keeps both YAML interfaces registry-neutral and lets custom destinations change authentication without YAML changes. The RubyGems helper does not retry or write credential files. See the [credential contract](docs/workflow/ruby_gems_credentials.md).

## Testing

The optional `ruby-gem-release/rspec` helper lets projects test their real workflow configuration with local Git, registry, and hosting adapters, without an RSpec runtime dependency. It does not rewrite production tasks or sandbox callbacks. See [Testing Custom Workflows](docs/testing.md); this repository's own suites are described in [CONTRIBUTING.md](CONTRIBUTING.md#tests).

## Self-Release and Artwork

This project releases itself with the manual `publish.yml` caller; see the [self-release walkthrough](examples/self_release/README.md).

`assets/logo.png` is an AI-generated faceted ruby with an upward release arrow, approved by the maintainer. It replaces the original AI-generated ruby rocket from [#5](https://github.com/dblock/ruby-gem-release/pull/5). Neither image has an editable source. The arrow-above-gem layout matches the sibling [JavaScript package release](https://github.com/dblock/npm-package-release) and [Rust crate release](https://github.com/dblock/rust-crate-release) logos. Keep this provenance and the 160-pixel README placement. A replacement should be a centered, text-free, red faceted ruby with an upward release motif on a transparent background. Generation is not deterministic, so inspect the full-size image and README rendering for clipping and legibility.
