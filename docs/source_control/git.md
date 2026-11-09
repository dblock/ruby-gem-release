# `RubyGemRelease::SourceControl::Git`

Owns local release commits and tags, branch checks, recovery bundles, and remote pushes.

## Branch and Remote

`Git.new(branch: nil, remote: 'origin', directory: nil)` uses `DEFAULT_BRANCH` or the remote's default-branch reference. The optional directory selects the recovery bundle and preparation index snapshot location; it defaults to a nonempty `RELEASE_DIRECTORY` or a new temporary directory. Separate Ruby processes must share this directory, as both Actions interfaces do through their execution provider.

## Configure

`configure!(name:, email:)` sets checkout-local identity. Direct-call defaults are `ruby-gem-release` and `ruby-gem-release@localhost`; blank values or line breaks fail. Context capture supplies the execution provider's identity, retaining the existing GitHub bot defaults on Actions.

## Head

`head` returns the current commit. `timestamp(commit)` reads the committer timestamp of a selected commit as Unix seconds; capture uses it for reproducible package timestamps.

## Check Current

`check_current!(release, expected: head, allow_ancestor: false)` fetches the remote branch and tags and rejects an advanced branch before new publication or pushing. Capture permits an ancestor checkout so reruns can use the original source commit after its release has advanced the branch.

## Check Tag

`check_tag!(version)` is an optional strict availability check. Standard publication instead reuses matching tags and rejects immutable conflicts after fetching.

## Commit

`commit!(release)` commits previously staged preparation changes if needed; it never stages files. It rejects unexpected unstaged, untracked non-ignored, or index changes by comparing the index with the saved preparation tree. It retains the initial commit for subsequent concurrency checks; the workflow supplies `RELEASE_INITIAL_COMMIT`.

## Clean Checkout and Preparation

`check_clean!` rejects any tracked changes, including staged changes, and any untracked non-ignored files. Diagnostics list escaped status paths, limit large listings, and suggest removing generated files, restoring unexpected changes, or intentionally ignoring dependency artifacts. Both Actions interfaces call it after dependency installation and before loading the gemspec or preparing release files. Existing ignore rules are honored, but tracked artifacts are never exempt.

`stage_changes! { ... }` requires a clean checkout, runs trusted preparation code, and stages the resulting paths with literal, argument-based Git invocation. This supports custom version, changelog, README, added, renamed, and deleted files without guessing conventions. Without a block, it stages current preparation outputs; the workflow uses this at the end of the configurable `prepare` command, before validation. It saves the exact index tree in `prepared-tree`, so even unrelated files staged later cannot silently enter publication. A failing block does not stage or commit its edits. Do not call this method from publication to accept unexpected validation output.

## Tag

`tag!(release)` rejects build mutations and concurrent advancement, reuses only a tag pointing at the exact release commit, and writes `release.bundle`. Conflicting tags fail.

## Commit Next

`commit_next!(release)` commits staged edits with a nonempty `next_version`; for `0.5.1`, the message is `Prepare next development iteration, 0.5.1`. Repetition reuses an existing direct child of the release only when its version and full prepared tree match. Otherwise, missing changes or conflicting state fail.

## Push

`push!(release)` checks the remote branch again, then atomically pushes the release commit and tag. After `commit_next!`, `push!` uses the retained release context and pushes only the next development iteration commit. Pushes never force or move existing tags.

Matching remote refs are no-ops; a remote branch already containing the release is never rewound. `commit!` can reuse an existing release tag only when its entire tree matches the intended preparation. `commit_next!` likewise compares the full development tree. Readback uses `tag_commit(version)`, `published?(version, commit:)`, and `next_iteration(release)`; no workflow state or artifact is restored. Unrelated advancement still fails before publication.

## Errors

Failed commands raise without retries. Publish the gem before the atomic push, as in [Usage](../../README.md#usage); this preserves the package-before-tag ordering but leaves a recovery window if pushing fails.
