# `RubyGemRelease::SourceControl::Git`

Handles the Git side of a release: clean and current checks, staging, the release commit and tag, a Git bundle (a one-file copy of the release for inspection), and pushes.

## Branch and Remote

`Git.new(branch: nil, remote: 'origin', directory: nil)` uses `DEFAULT_BRANCH` or the remote's default branch. `directory:` holds the bundle and the staged-tree snapshot; it defaults to a nonempty `RELEASE_DATA_DIR` or a new temporary directory, created on first use. Separate Ruby processes must share it, as both Actions interfaces do through their execution provider.

## Configure

`configure!(name:, email:)` sets the commit identity for this checkout only. Direct calls default to `ruby-gem-release` and `ruby-gem-release@localhost`; blank values or line breaks raise. The workflow passes the execution provider's identity, the GitHub bot on Actions.

## Head

`head` returns the current commit. `timestamp(commit)` returns its committer time in Unix seconds, used for reproducible package timestamps.

## Check Current

`check_current!(expected: head, allow_ancestor: false)` fetches the remote branch and tags and raises if the branch moved. Capture allows an ancestor, so a rerun can use the original source commit after its release advanced the branch.

## Commit

`commit!(release)` commits staged preparation changes, if any; it never stages. Unstaged changes, untracked files that are not ignored, or an index that differs from the saved preparation raise. It keeps the source commit (`SOURCE_COMMIT` in the workflow) for later checks. An existing release tag is reused only when its whole tree matches.

## Clean Checkout and Preparation

`check_clean!` raises on any tracked change, staged or not, and any untracked file that is not ignored. Ignore rules apply, but tracked files are never exempt. The error lists the paths and suggests deleting generated files, restoring changes, or ignoring dependency output. Both Actions interfaces call it after installing dependencies and before loading the gemspec or editing files.

`stage_changes! { ... }` requires a clean checkout, runs your trusted preparation block, and stages every changed path, including added, renamed, and deleted files, with literal Git arguments. Without a block, it stages current changes; the workflow does this after the `prepare` command, before tests. It saves the staged tree as `prepared-tree`, so files staged later cannot slip into the release. If the block raises, nothing is staged. Do not call it during publication to accept unexpected test output.

## Tag

`tag!(release)` raises if the build changed the checkout or the branch moved, reuses a tag only when it points at the release commit, and writes `release.bundle`. A tag on another commit raises.

## Commit Next

`commit_next!(release)` commits staged edits for a nonempty `next_version`, as `Prepare next development iteration, 0.5.1` for `0.5.1`. There must be changes. A rerun reuses a commit right after the release only when its version and full tree match; anything else raises.

## Push

`push!(release)` rechecks the remote branch, then pushes the release commit and tag in one atomic push. After `commit_next!`, it pushes only the next-version commit. It never force-pushes or moves tags.

Reruns are safe: matching remote refs are skipped and a branch that already contains the release is never rewound. `tag_commit(version)` and `next_iteration(release)` read back existing commits; no state or artifact is restored. Unrelated new commits still raise before publication.

## Errors

Failed commands raise without retries. Publish the gem before the atomic push, as in [Usage](../../README.md#usage): the gem then always exists before its tag, but a failed push needs recovery.
