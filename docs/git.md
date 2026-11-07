# `RubyGemRelease::Git`

Owns local release commits and tags, branch checks, recovery bundles, and remote pushes.

## Branch and Remote

`Git.new(branch: nil, remote: 'origin', directory: nil)` uses `DEFAULT_BRANCH` or the remote's default-branch reference. The optional directory selects the recovery bundle location; it defaults to `RUNNER_TEMP` or a new temporary directory.

## Configure

`configure!(name:, email:)` sets checkout-local identity. Defaults are `github-actions[bot]` and `github-actions[bot]@users.noreply.github.com`; blank values or line breaks fail. The workflow calls this with its identity inputs.

## Head

`head` returns the current commit.

## Check Current

`check_current!(release, expected: head)` fetches the remote branch and tags and rejects an advanced branch before publication or pushing. Dry runs fetch but permit a non-default-branch checkout.

## Check Tag

`check_tag!(version)` rejects an existing `vVERSION` tag. The workflow calls it before validation; tagging checks again after fetching.

## Commit

`commit!(release)` stages release changes and creates a preparation commit if needed. It retains the initial commit for subsequent concurrency checks; the workflow supplies `RELEASE_INITIAL_COMMIT`.

## Tag

`tag!(release)` rejects checkout mutations from building, checks concurrency and existing tags, creates `vVERSION`, and writes `release.bundle` containing the exact commit and tag. Local tagging also runs in dry runs.

## Commit Next

`commit_next!(release)` commits next-version changes and fails if no files changed. It retains the published commit for the next push's concurrency check.

## Push

`push!(release)` checks the remote branch again, then atomically pushes the release commit and tag. After `commit_next!`, `push!` uses the retained release context and pushes only the next-version commit. Both skip remote writes when `release.dry_run?` is true. Pushes never force or move existing tags.

## Errors

Failed commands raise without retries. Publish the gem before the atomic push, as in [Usage](../README.md#usage); this preserves the package-before-tag ordering but leaves a recovery window if pushing fails.
