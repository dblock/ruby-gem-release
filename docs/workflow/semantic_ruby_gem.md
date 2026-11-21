# `RubyGemRelease::Workflow::SemanticRubyGem`

The semantic workflow picks the next version from commit messages instead of handwritten changelog notes. Setup and the manually dispatched Actions workflow match the [standard workflow](ruby_gem.md); it adds no automatic triggers.

```ruby
require 'ruby-gem-release/workflow/semantic_ruby_gem'

RubyGemRelease::Workflow::SemanticRubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION')
).install_tasks
```

Install only one workflow. The provider, package, destination, Git, hosting, and callbacks are still replaceable. [Lifecycle hooks](hooks.md) can read the release decision and version after validation; development hooks run only with `bump: true`.

## History and Versions

The last release is the highest stable `vMAJOR.MINOR.PATCH` tag reachable from the current commit, not the nearest or newest. Annotated and lightweight tags count; prerelease, metadata, other-format, and unreachable tags do not. Shallow checkouts fail, so check out full history.

Commits after that tag are analyzed, or all commits if there is none. The first release is `1.0.0` whatever the commits say. To change it:

```ruby
semantic = RubyGemRelease::SemanticRelease.new(
  selector: RubyGemRelease::SemanticRelease::VersionSelector.new(first_version: '0.1.0')
)

RubyGemRelease::Workflow::SemanticRubyGem.new(
  version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
  semantic_release: semantic
).install_tasks
```

Later releases increment the last release and reset lower parts, for example `1.2.3` to `1.3.0`. Development versions are ignored; `ctx.analysis.last_release` holds the last release.

An explicit `version` input forces a release, even without releasable commits. It must be higher than the last release. Preparation writes it with `set!`, and later steps must see the same version.

## Conventional Commits

The default analyzer reads [Conventional Commits](https://www.conventionalcommits.org/) headers like `type(scope)!: description` and `BREAKING CHANGE:` or `BREAKING-CHANGE:` notes. The highest match wins:

- A breaking change selects a major release.
- `feat` selects minor.
- `fix`, `perf`, and a Git revert of an older change select patch.
- Other types and unstructured messages select nothing.

A commit and its revert in the analyzed range cancel out, even with an abbreviated hash.

Custom rules use symbol keys and shell-style globs (`File.fnmatch?`), not JavaScript micromatch:

```ruby
analyzer = RubyGemRelease::SemanticRelease::ConventionalCommits.new(
  rules: [
    { type: 'docs', scope: 'api*', release: :patch },
    { scope: 'no-release', release: false }
  ]
)

semantic = RubyGemRelease::SemanticRelease.new(analyzer: analyzer)
```

A rule matches `type`, `scope`, and `subject` strings and boolean `breaking` and `revert`; all its selectors must match. `release:` is `:major`, `:minor`, `:patch`, or `false`. Matching rules replace the defaults for that commit: the highest positive match wins, otherwise `false` suppresses it. Unmatched commits use the defaults.

If no commit is releasable, validation raises and the failure callback reports it; pending notes do not count. An optional `validate:` callback must raise on invalid state, and returning `false` also fails. It receives the starting context; later tasks see the recorded analysis.

## Notes and Changelog

Generated notes group features, fixes, performance improvements, and other changes with short commit hashes, and list breaking changes separately. Canceled reverts are left out. Headers are escaped for Markdown; breaking-change text keeps its Markdown. Notes have no host URLs. A forced release with no commits gets an explicit-version note.

The default `Changelog::Generated` creates `CHANGELOG.md` if missing and inserts a dated `## VERSION (YYYY/MM/DD)` section above existing second-level sections, keeping the rest of the file and its line endings. Use it only for a generated changelog, not one with a handwritten pending section. It rejects duplicate headings and empty notes, never adds an unreleased section, and is not changed by a development bump.

Set `changelog: nil` to skip file updates, or pass an object whose `release!(release)` uses `release.notes`; with `bump: true` it also needs `prepare_next!(release)`. Handwritten changelog classes do not switch to generated notes.

GitHub hosting uses `release.notes` unchanged; the manual workflows use `--generate-notes`. Custom hosting must use the supplied notes and exact artifact, not analyze commits again.

## Development Iterations

With the default `bump: false`, the bump task does nothing and `release.next_version` stays `nil`. `bump: true` increments, commits, and pushes the next version, using patch unless [`next_version:`](ruby_gem.md#next-version) says otherwise. Selection still uses release tags. Manual workflows always bump.

## State and Callbacks

Validation records one immutable `SemanticRelease::Decision` with `ctx.record_analysis!`:

- `head`: the analyzed commit.
- `last_release`: `nil`, or a frozen hash with string keys `tag`, `version`, and `commit`.
- `commits`: every analyzed commit, including canceled ones, as frozen hashes with `sha` and full `message`.
- `release_type`, `version`, `notes`: all `nil` when nothing is released.
- `explicit_version`: the forced version, if any.

Later contexts read this saved decision without rerunning providers. The private JSON state file holds only `analysis` and `next_version`. Corrupt state or unknown fields fail the release. Failure reports skip unreadable state with a warning and still report the original error.

Keep `RELEASE_STATE_FILE` and captured inputs across processes. If `SOURCE_COMMIT`, the explicit input, or the prepared version changes, the release fails before publication. Separate processes need private storage and a way to pass exported values.

## Replacing Providers

`SemanticRelease.new` accepts independently replaceable providers:

| Provider    | Contract                                                                                                                                          |
| ---         | ---                                                                                                                                               |
| `history:`  | `read(head:)` returns `{ last_release:, commits: }` using the decision's string-keyed history shapes.                                             |
| `analyzer:` | `analyze(commits)` returns `"major"`, `"minor"`, `"patch"`, or `nil`.                                                                             |
| `selector:` | `select(last_release:, release_type:, explicit_version:)` receives the last version string or `nil` and returns a stable version string or `nil`. |
| `notes:`    | `generate(commits:, version:, last_release:)` returns nonempty Markdown for a selected release.                                                   |

`SemanticRelease` validates, copies, and freezes each result. A custom history provider must keep default-branch ancestry checks and return complete history. No provider may publish, change Git refs, or weaken selection checks. The [GitLab example](../../examples/gitlab_semantic_release/README.md) combines the real providers with deliberately unfinished platform adapters.

## Compatibility and Scope

This Ruby code follows the stable-release behavior of [semantic-release v25.0.9](https://github.com/semantic-release/semantic-release/tree/v25.0.9), [commit-analyzer v13.0.1](https://github.com/semantic-release/commit-analyzer/tree/v13.0.1), and [release-notes-generator v14.1.1](https://github.com/semantic-release/release-notes-generator/tree/v14.1.1). It does not port their JavaScript plugins, presets, or note templates, and needs no Node.

Not supported yet: prereleases, maintenance branches, distribution channels, other tag formats, and other CI platforms. The usual clean-checkout, concurrency, and exact-artifact checks still apply, and an already-published version passes only if its SHA256 matches. Unlike upstream, the package is verified or uploaded before the commit and tag are pushed together. Reruns use the [current checkout and inputs](../../RELEASING.md#verify-and-recover), not a saved analysis.
