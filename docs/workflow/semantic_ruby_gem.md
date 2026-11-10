# `RubyGemRelease::Workflow::SemanticRubyGem`

Select releases from commits instead of handwritten pending notes. Keep the same [runtime and release setup](ruby_gem.md) and manually dispatched Actions interface; this does not enable triggers or authorize publication.

```ruby
require 'ruby-gem-release/workflow/semantic_ruby_gem'

RubyGemRelease::Workflow::SemanticRubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION')
).install_tasks
```

Install only one workflow. Execution, package, destination, Git, hosting, and result callbacks remain independently replaceable.

## History and Versions

Validation selects the highest reachable stable `vMAJOR.MINOR.PATCH` tag, not the nearest or newest. Annotated and lightweight tags work; unrelated, prerelease, metadata, and alternate-format tags are ignored. Shallow checkouts fail. Capture fetches tags and checks remote advancement; supply full history.

Analysis covers all reachable commits initially, then commits after the selected tag. First release defaults to `1.0.0` regardless of severity; override it with:

```ruby
semantic = RubyGemRelease::SemanticRelease.new(
  selector: RubyGemRelease::SemanticRelease::VersionSelector.new(first_version: '0.1.0')
)

RubyGemRelease::Workflow::SemanticRubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
  semantic_release: semantic
).install_tasks
```

Later versions increment the last release, resetting lower components. Development versions do not affect selection. `release.gemspec_version` remains the initial gemspec version; `ctx.analysis.last_release` is the release baseline.

Explicit `version` can force a release without releasable commits. It must exceed the last release, not necessarily the development or suggested version. The version object needs `set!`; all later phases must match the persisted selection.

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

No releasable commits raises a validation error before downstream operations; the failure callback reports it. Handwritten pending notes do not affect selection. Optional `validate:` raises on invalid state; returning `false` also fails. Its context is the starting snapshot, while subsequent tasks see newly recorded analysis.

## Notes and Changelog

Generated notes group features, fixes, performance improvements, and other changes, include short commit identifiers, and list breaking-change descriptions separately. Canceled revert pairs are omitted. Headers are escaped for Markdown; breaking descriptions retain their Markdown. Notes are platform-neutral, without guessed host URLs. A forced release with no commits has an explicit-version note.

The default `Changelog::Generated` creates `CHANGELOG.md` if absent or inserts a dated `## VERSION (YYYY/MM/DD)` section before existing second-level sections, preserving historical source and line endings. Use it with a dedicated generated changelog, not a handwritten pending-section convention. It rejects duplicate release headings and content-free notes. It does not create an unreleased section or edit the changelog during a development bump.

Set `changelog: nil` to disable file updates, or supply an object whose `release!(release)` consumes `release.notes`. With `bump: true`, also implement `prepare_next!(release)`. A handwritten changelog provider is not automatically converted to generated notes.

GitHub hosting passes frozen `release.notes` verbatim through a private file; manual workflows retain `--generate-notes`. Custom hosting must use supplied notes and the exact artifact, not reanalyze.

## Development Iterations

With default `bump: false`, the installed bump task does nothing and `release.next_version` stays `nil`. `bump: true` enables the standard patch increment, commit, and push. Future selection still uses released tags. Manual workflows continue to bump automatically.

## State and Callbacks

Validation records one immutable `SemanticRelease::Decision` through `ctx.record_analysis!`. Its fields are `head`, `last_release`, `commits`, `release_type`, `version`, `notes`, and `explicit_version`. `last_release` is `nil` or a frozen hash with string keys `tag`, `version`, and `commit`. `commits` retains the full analyzed range as frozen hashes with `sha` and complete `message`, including commits canceled for release analysis. A no-release decision has `nil` release type, version, and notes.

Later contexts expose persisted analysis without rerunning providers or mutating earlier snapshots. Private JSON supports schema 2; recording a bump preserves analysis. Corrupt or legacy state fails closed. Failure reporting uses one coherent snapshot, warning and omitting unreadable state without hiding the original error.

Preserve `RELEASE_STATE_FILE` and captured inputs across processes. Changed `SOURCE_COMMIT`, explicit input, or prepared version fails before publication. In-process tasks can share memory; separate processes need private storage and export transport.

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

Prereleases, maintenance branches, distribution channels, alternate tag formats, and additional CI-platform adapters are outside this first implementation. Clean-checkout, concurrency, preparation, and exact-artifact checks remain; an already-published version succeeds only on matching SHA256. Unlike upstream, this project verifies or uploads the package before atomically pushing commit and tag. Reruns use the [current checkout and inputs](../../RELEASING.md#verify-and-recover), not restored analysis.
