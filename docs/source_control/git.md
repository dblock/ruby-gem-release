# `RubyGemRelease::SourceControl::Git`

Owns local release commits and tags, branch checks, recovery bundles, and remote pushes.

## Branch and Remote

`Git.new(branch: nil, remote: 'origin', directory: nil)` uses `DEFAULT_BRANCH` or the remote's default-branch reference. The optional directory selects the recovery bundle and preparation index snapshot location; it defaults to a nonempty `RELEASE_DIRECTORY` or a new temporary directory. Separate Ruby processes must share this directory, as both Actions interfaces do through their execution provider.

## Configure

`configure!(name:, email:)` sets checkout-local identity. Direct-call defaults are `ruby-gem-release` and `ruby-gem-release@localhost`; blank values or line breaks fail. Context capture supplies the execution provider's identity, retaining the existing GitHub bot defaults on Actions.

## Head

`head` returns the current commit.

## Check Current

`check_current!(release, expected: head)` fetches the remote branch and tags and rejects an advanced branch before publication or pushing.

## Check Tag

`check_tag!(version)` rejects an existing `vVERSION` tag. The workflow calls it before validation; tagging checks again after fetching.

## Commit

`commit!(release)` commits previously staged preparation changes if needed; it never stages files. It rejects unexpected unstaged, untracked non-ignored, or index changes by comparing the index with the saved preparation tree. It retains the initial commit for subsequent concurrency checks; the workflow supplies `RELEASE_INITIAL_COMMIT`.

## Clean Checkout and Preparation

`check_clean!` rejects any tracked changes, including staged changes, and any untracked non-ignored files. Diagnostics list escaped status paths, limit large listings, and suggest removing generated files, restoring unexpected changes, or intentionally ignoring dependency artifacts. Both Actions interfaces call it after dependency installation and before loading the gemspec or preparing release files. Existing ignore rules are honored, but tracked artifacts are never exempt.

`stage_changes! { ... }` requires a clean checkout, runs trusted preparation code, and stages the resulting paths with literal, argument-based Git invocation. This supports custom version, changelog, README, added, renamed, and deleted files without guessing conventions. Without a block, it stages current preparation outputs; the workflow uses this at the end of the configurable `prepare` command, before validation. It saves the exact index tree in `prepared-tree`, so even unrelated files staged later cannot silently enter publication. A failing block does not stage or commit its edits. Do not call this method from publication to accept unexpected validation output.

## Tag

`tag!(release)` rejects checkout mutations from building, checks concurrency and existing tags, creates `vVERSION`, and writes `release.bundle` containing the exact commit and tag.

## Commit Next

`commit_next!(release)` commits changes previously staged with `stage_changes!` and fails if no files changed. The context must include a nonempty `next_version`, obtained with `release.with_next_version(version.increment!)`. For `next_version: '0.5.1'`, the commit message is `Prepare next development iteration, 0.5.1`. It retains the published commit for the next push's concurrency check.

## Push

`push!(release)` checks the remote branch again, then atomically pushes the release commit and tag. After `commit_next!`, `push!` uses the retained release context and pushes only the next development iteration commit. Pushes never force or move existing tags.

## Errors

Failed commands raise without retries. Publish the gem before the atomic push, as in [Usage](../../README.md#usage); this preserves the package-before-tag ordering but leaves a recovery window if pushing fails.
