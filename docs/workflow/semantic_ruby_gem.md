# `RubyGemRelease::Workflow::SemanticRubyGem`

Opt into commit-driven releases instead of the default checked-in version and handwritten pending notes. This workflow requires the same Ruby and release environment as [`Workflow::RubyGem`](ruby_gem.md); it does not enable automatic triggers or authorize publication. Keep the existing manually dispatched Actions workflow or composite action.

```ruby
require 'ruby-gem-release/workflow/semantic_ruby_gem'

RubyGemRelease::Workflow::SemanticRubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION')
).install_tasks
```

Install only one workflow. The semantic workflow accepts the same independent execution provider, package, destination, Git, hosting, and result callbacks as the manual workflow. GitHub Actions remains the only built-in external execution platform.

## History and Versions

Validation reads stable `vMAJOR.MINOR.PATCH` tags reachable from the captured default-branch commit and chooses the highest numeric version, not the nearest tag or newest tag date. Annotated and lightweight tags work. Tags on unrelated branches, prerelease tags, build metadata, and other naming conventions are ignored. Shallow checkouts fail explicitly; fetch complete history and tags before capture. The built-in Git capture fetches tags and checks that the default branch has not advanced.

Analyze all reachable commits for a first release, or commits after the selected tag otherwise. The first releasable version defaults to `1.0.0` regardless of release type, matching semantic-release. Configure another starting version when needed:

```ruby
semantic = RubyGemRelease::SemanticRelease.new(
  selector: RubyGemRelease::SemanticRelease::VersionSelector.new(first_version: '0.1.0')
)

RubyGemRelease::Workflow::SemanticRubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
  semantic_release: semantic
).install_tasks
```

Subsequent versions increment the last released version: major resets minor and patch, minor resets patch, and patch increments patch. A checked-in development version such as `9.9.9` does not affect a selection from released `1.2.3`. `release.previous_version` continues to mean the initial gemspec version; `ctx.analysis.last_release` identifies the actual release baseline.

The existing explicit `version` input takes precedence, including allowing a release with no releasable commits. It must be a stable numeric version strictly greater than the last release; it need not exceed the checked-in development version or the automatically suggested version. The version object must implement `set!`; preparation, resolution, and publication must all agree on the persisted selection.

## Conventional Commits

The default analyzer understands `type(scope)!: description` headers and multiline `BREAKING CHANGE:` or `BREAKING-CHANGE:` notes. Breaking changes select major; `feat` selects minor; `fix` and `perf` select patch. A Git revert of an older change selects patch. Original/revert pairs within the analyzed range cancel each other, including abbreviated commit references. Other commit types and unstructured messages do not select a release by default. The highest applicable release type wins.

Custom rules use Ruby symbol keys and shell-style glob matching through `File.fnmatch?`, not JavaScript micromatch:

```ruby
analyzer = RubyGemRelease::SemanticRelease::ConventionalCommits.new(
  rules: [
    { type: 'docs', scope: 'api*', release: :patch },
    { scope: 'no-release', release: false }
  ]
)

semantic = RubyGemRelease::SemanticRelease.new(analyzer: analyzer)
```

Supported selectors are `type`, `scope`, and `subject` strings, plus boolean `breaking` and `revert` selectors. A rule matches when all its selectors match. Matching custom rules replace defaults for that commit; the highest positive match wins, or `false` suppresses it if there is no positive match. Unmatched commits fall back to defaults. Use `release: :major`, `:minor`, `:patch`, or `false`.

No releasable commits means `proceed=false`, without preparation, authentication, publication, development bumps, or success notifications. This decision does not consult handwritten pending changelog content. An optional `validate:` callback can additionally veto a releasable decision; it receives the validation task's starting snapshot, while newly recorded analysis is visible to subsequent tasks.

## Notes and Changelog

Generated notes group features, fixes, performance improvements, and other changes, include short commit identifiers, and list breaking-change descriptions separately. Canceled revert pairs are omitted. Headers are escaped for Markdown; breaking descriptions retain their Markdown. Notes are platform-neutral, without guessed host URLs. A forced release with no commits has an explicit-version note.

The default `Changelog::Generated` creates `CHANGELOG.md` if absent or inserts a dated `## VERSION (YYYY/MM/DD)` section before existing second-level sections, preserving historical source and line endings. Use it with a dedicated generated changelog, not a handwritten pending-section convention. It rejects duplicate release headings and content-free notes. It does not create an unreleased section or edit the changelog during a development bump.

Set `changelog: nil` to disable file updates, or supply an object whose `release!(release)` consumes `release.notes`. With `bump: true`, also implement `prepare_next!(release)`. A handwritten changelog provider is not automatically converted to generated notes.

The same frozen `release.notes` reaches hosting. Built-in GitHub hosting passes it verbatim through a private temporary notes file instead of requesting platform-generated notes. Manual workflows retain `--generate-notes`. Custom hosting should use the supplied notes and exact artifact, not reanalyze commits.

## Development Iterations

Semantic workflows default to `bump: false`. The existing bump task remains installed but does nothing, and `release.next_version` remains `nil`. Set `bump: true` to retain the standard patch increment, next-development commit, and push. Future semantic selection still uses the last release tag, not that development version. Manual workflows retain their existing automatic patch bump.

## State and Callbacks

Validation records one immutable `SemanticRelease::Decision` through `ctx.record_analysis!`. Its fields are `head`, `last_release`, `commits`, `release_type`, `version`, `notes`, and `explicit_version`. `last_release` is `nil` or a frozen hash with string keys `tag`, `version`, and `commit`. `commits` retains the full analyzed range as frozen hashes with `sha` and complete `message`, including commits canceled for release analysis. A skipped decision has `nil` release type, version, and notes.

Later tasks load the decision rather than re-running providers. Contexts are snapshots: recording analysis does not modify the validation context already passed to the callback. Prepared and published contexts expose it through `ctx.analysis`; failure contexts include it when readable. Versioned private JSON state supports schema 2 decisions and legacy schema 1 next-version data. Recording a development version preserves analysis. Corrupt or unsupported state fails closed; failure reporting warns and omits unreadable state without hiding the original error.

Preserve `RELEASE_STATE` and captured inputs across processes. Decisions are bound to `RELEASE_INITIAL_COMMIT` and the original explicit version. Changed inputs or a mismatched prepared version fail before publication. In-process tasks can share memory without a file, but separate local processes need a provider with private storage and export transport.

## Replacing Providers

`SemanticRelease.new` accepts independently replaceable providers:

| Provider    | Contract                                                                                                                                          |
| ---         | ---                                                                                                                                               |
| `history:`  | `read(head:)` returns `{ last_release:, commits: }` using the decision's string-keyed history shapes.                                             |
| `analyzer:` | `analyze(commits)` returns `"major"`, `"minor"`, `"patch"`, or `nil`.                                                                             |
| `selector:` | `select(last_release:, release_type:, explicit_version:)` receives the last version string or `nil` and returns a stable version string or `nil`. |
| `notes:`    | `generate(commits:, version:, last_release:)` returns nonempty Markdown for a selected release.                                                   |

`SemanticRelease` validates, copies, and freezes the result. Custom history providers must preserve default-branch ancestry checks and complete history. Custom providers must not publish, alter Git refs, or weaken selection guards. The [GitLab example](../../examples/gitlab_semantic_release/README.md) composes real semantic providers with explicitly unfinished platform adapters.

## Compatibility and Scope

The Ruby implementation follows stable-release behavior from [semantic-release v25.0.9](https://github.com/semantic-release/semantic-release/tree/v25.0.9), [commit-analyzer v13.0.1](https://github.com/semantic-release/commit-analyzer/tree/v13.0.1), and [release-notes-generator v14.1.1](https://github.com/semantic-release/release-notes-generator/tree/v14.1.1), including highest reachable stable version, first release `1.0.0`, Conventional Commits severity, custom-rule fallback, and revert cancellation. It is not a port of their JavaScript plugin system, presets, or note templates and adds no Node dependency.

Prereleases, maintenance branches, distribution channels, alternate tag formats, and additional CI-platform adapters are outside this first implementation. Existing clean-checkout, duplicate-version, concurrency, preparation, and exact-artifact checks remain intact. Unlike the upstream tag-push ordering, this project continues to upload the verified package before atomically pushing its release commit and tag; review [recovery instructions](../../RELEASING.md) before retrying a failed publication.
