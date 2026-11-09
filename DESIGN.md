# Design

`ruby-gem-release` provides a reusable GitHub Actions workflow, a composite action, and Ruby lifecycle tasks. Projects choose version and changelog conventions; replaceable components retain one publication sequence.

## Component Boundaries

| Component                   | Responsibility                                                                       |
| ---                         | ---                                                                                  |
| `Workflow::RubyGem`         | Install the manual release callbacks.                                                |
| `Workflow::SemanticRubyGem` | Select and persist a commit-driven release, then use the same publication sequence.  |
| `Tasks`                     | Register callbacks, construct contexts, and capture failures.                        |
| `ExecutionProvider`         | Transport inputs, exports, outputs, execution metadata, and authentication services. |
| `Workflow::Environment`     | Check the checkout and capture initial or prepared package metadata.                 |
| `Workflow::State`           | Persist supported callback data in private, versioned JSON.                          |
| `Package::RubyGem`          | Read metadata, build reproducibly, and verify the exact archive.                     |
| `Destination::RubyGems`     | Authenticate, check availability, and upload the verified artifact.                  |
| `SourceControl::Git`        | Stage trusted edits, check concurrency, commit, tag, and push.                       |
| `Hosting::GitHubRelease`    | Create the hosted release after the remote tag exists.                               |

Execution platform, registry, and hosting are independent choices. Built-in external support covers GitHub Actions, RubyGems, and GitHub Releases. Hosting providers need `publish!(release, package:)` and read-only `published?(release, package:)`, not a shared base class. Class, reference, and spec paths mirror namespaces.

## Lifecycle and Publication

Both interfaces install dependencies, capture context, validate, prepare files, resolve the version, test, checkpoint and preserve artifacts, publish, prepare the next development iteration, and notify success. Validation raises on invalid state, including nothing to release; normal completion succeeds, while returning `false` also fails. Errors stop downstream operations and reach the failure callback after successful Ruby setup.

The standard publication callback commits prepared edits, builds reproducibly, tags locally and creates a recovery bundle, verifies or uploads the gem, atomically pushes its commit and tag, and creates or updates the hosted release. Git checks for concurrent branch changes before publication and again before pushing.

Every release action must be idempotent for the same checkout and inputs, without recovery flags, artifact discovery, restored context, or a completion journal. Tasks reconcile their own outputs; a fresh workflow uses its current checkout and inputs rather than discovering an older unfinished release. Registry publication and Git pushes cannot be atomic together, so both interfaces preserve artifacts before publication for manual inspection. See [rerunning releases](RELEASING.md#verify-and-recover).

Keep both YAML interfaces thin and consistent. The reusable workflow does not depend on a moving composite-action reference: a pinned release must remain independent of later action versions. Composite callers own permissions, runner, environment protection, and concurrency. Commands run with release privileges and must be trusted.

## Preparation and Artifact Guards

Capture rejects non-default branches and dirty checkouts after dependency installation. Capture and resolution use the configured package; built-in selection requires one root gemspec or an explicit path. Dates and the initial version are captured once, with UTC as the timezone default.

`Git#stage_changes!` requires a clean checkout or the exact previously prepared index before trusted edits, stages literal changed paths, and records the index tree. Resolution also stages custom preparation-command outputs before testing. Publication rejects later working-tree or index changes and never stages them. Development iteration edits use the same boundary, including custom version-object side effects.

Resolution validates the prepared version; publishing tasks enforce their own postconditions. RubyGems accepts an existing version only when its checksum matches. Git reuses matching release and development trees without moving tags or rewinding remote descendants. Hosting replaces differing metadata and assets. Development increments are anchored to the supplied release version, not a recorded completion marker.

Version objects update exactly one constant assignment without evaluating the file. Changelog objects use `Commonmarker` to find sections, then edit original source to preserve formatting. Handwritten formats reject empty notes before writing; malformed content fails rather than skipping. See [version](docs/version/ruby_constant.md), [changelog](docs/changelog/base.md), and [Git](docs/source_control/git.md) contracts.

## Contexts and State

Callbacks receive frozen execution snapshots containing an immutable `Release`, current step, observed history, configured workflow, run metadata, and optional semantic analysis. Domain operations receive only `Release`. Contexts are data, not platform clients; workflow objects are reconstructed from the Rakefile in each process.

The provider-neutral base uses logical task IDs and process-local outputs. Automatic selection chooses GitHub when `GITHUB_ACTIONS=true`; explicit `provider:` overrides detection. GitHub owns Actions transport, refs, temporary storage, bot identity, masking, and OIDC. It supplies enclosing step IDs and prior observed results, keeping outcome and conclusion distinct. Absent steps are unknown, not skipped; run metadata excludes credentials and the event payload.

Capture creates a unique private state file outside the checkout when provider storage is available. Atomic updates retain semantic analysis and the completed next development version; legacy schema 1 remains readable. Regular callback contexts read one validated snapshot, without caching across invocations. Without a file, tasks share process-local state. Corrupt state fails closed; failure callbacks omit unreadable metadata without hiding the original exception.

Failure callbacks receive the failed phase, captured Ruby exception when available, and context whose release may be absent. Shell-only failures may lack exception details. See [execution contexts](docs/execution_context.md) and [tasks](docs/tasks.md).

## Manual and Semantic Workflows

The manual workflow requires explicit version and changelog choices. Preparation honors an optional version selection; publication retains the initial version separately. After publication, the default bump increments patch, prepares the next changelog section, commits, pushes, and records the next version. `changelog: nil` and `hosting: nil` disable only those components.

Semantic releases are opt-in. Validation analyzes commits after the highest reachable stable release tag, records one immutable decision, and binds it to the captured head and explicit input. Later phases consume it without reanalysis. Versions do not derive from development versions; first release defaults to `1.0.0`, and explicit versions must exceed the last release. Generated notes reach the changelog and hosting unchanged.

Semantic development bumps default off. Prereleases, maintenance branches, channels, alternate tag formats, and additional platform adapters remain outside scope. Provider contracts and upstream behavior references live in the [semantic guide](docs/workflow/semantic_ruby_gem.md).

## Authentication

Authentication belongs to `release:publish`, through the destination's `authenticate!(provider:)` hook, not a registry-specific YAML step. RubyGems uses `Workflow::RubyGemsCredentials` when resolution selected automatic authentication; other destinations can retain preconfigured credentials.

The helper obtains an audience-bound token through its execution provider, exchanges it with optional owner binding, masks tokens, and exports key variables. It makes no retries or credential-file writes. Custom callbacks inherit that environment; commands bypassing the publication task own authentication. See the [credential contract](docs/workflow/ruby_gems_credentials.md).

## Testing

Source CI runs `rake spec:unit`; installed-gem CI runs `rake spec:integration`. The default local task runs both plus lint. Focused specs cover orchestration permutations, documented configurations, and YAML shell contracts without repeated Bundler startup.

Real-process consumers retain success, failure/recovery, empty-release rejection, custom registry, and credential propagation. Portable consumers also verify environment transport, state, and installed-library loading without Actions variables. Git pushes use local bare repositories; publication boundaries are isolated and unexpected network requests fail. These tests do not validate live Actions authentication or artifact uploading. Profile harness changes rather than enforcing timing thresholds.

## Self-Release and Artwork

The manual `publish.yml` caller uses the root Rakefile and Ruby 4.0; merges and schedules do not publish. Every dispatch requires release authorization. Its project-local `ReleaseVersion` updates README pins during the next development iteration, after the release tag exists. See the [self-release walkthrough](examples/self_release/README.md).

`assets/logo.png` is the original AI-generated ruby rocket; no editable source was provided. Preserve its provenance and 160-pixel README placement. Replacements should be centered, text-free red faceted rubies with an upward launch motif and transparent background. Generation is not deterministic; inspect the full-size image and README rendering for clipping and legibility.
