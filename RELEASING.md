# Releasing

These instructions describe the reusable release workflow; they do not authorize a release or publication.

## One-Time Setup

Add a caller workflow as shown in [README.md](README.md), with `contents: write` and `id-token: write`, and create a GitHub environment named `release` in the publishing repository. This repository does not yet have a release caller configured. Restrict environment deployment branches and require approval when available. Configure the gem's [RubyGems trusted publisher](https://guides.rubygems.org/trusted-publishing/) with the publishing repository and `release` environment, workflow filename `release.yml`, and workflow repository owner `dblock` and name `ruby-gem-release` when calling from another repository. For a first release, configure a pending trusted publisher. The workflow uses short-lived OIDC credentials, not a stored RubyGems API key.

The GitHub Actions token must be permitted to push fast-forward commits and tags to the default branch. Rulesets with a PR requirement may block it; a dedicated release App bypass can preserve PR enforcement if configured. This repository's ruleset instead allows all writers to push directly while blocking force pushes and deletion; ordinary changes still go through PRs. Actions-token pushes do not trigger ordinary push workflows, so the caller's validation command must run the necessary checks.

## Prepare and Publish

Review the changes, choose a numeric `MAJOR.MINOR.PATCH` version, and dispatch the caller workflow on the current default branch. Approve the `release` environment if required. By default, `prepare` sets the version using the installed Rake task, `validate` runs `bundle exec rake`, and `bump` increments the patch version. Override these commands to update project-specific release files or run different checks. The workflow commits changes, builds once, verifies the built gem version, creates a local tag, and preserves the gem and a Git bundle containing the release commit and tag for 30 days. It checks that the default branch has not advanced before publishing the artifact to RubyGems, then atomically pushes the release commit and tag and creates a GitHub Release with the same gem. Finally, the `bump` command must change files to the next development version, which the workflow commits and pushes.

For a non-publishing integration check, set `dry-run: true` in the caller. The shared workflow skips its RubyGems authentication, publication, pushes, and GitHub Release creation, but still runs caller-provided commands and creates local commits and a tag. Those commands must themselves be safe; dry-run cannot constrain what they do. Never use untrusted commands or untrusted workflow inputs.

## Verify and Recover

Verify the version on RubyGems, the tag's commit, the GitHub Release and attached gem, and the next development version on the default branch. Never overwrite published versions or move release tags.

Publication precedes the atomic commit/tag push, so a concurrent branch update or network failure can leave a published gem without a remote tag. Before retrying any failed or timed-out upload, check RubyGems: the server may have accepted it. If the gem was published, do not rerun the full workflow. Recover the exact release commit from the run logs and the preserved artifact, reconcile concurrent changes without rewriting history, and push the matching commit and tag only after verifying their identity. If the tag exists but the GitHub Release is missing, create it from that tag and attach the preserved artifact. If the release succeeded but the bump failed, update only the missing next-version commit after verifying the current branch and published version.

Artifact retention is finite; download the run artifact promptly when recovery is needed. Fetch the original commit and tag from the preserved Git bundle, inspect them, and compare the preserved gem with the publication before completing recovery. If the default branch advanced, coordinate recovery rather than moving its history or tagging another commit.
