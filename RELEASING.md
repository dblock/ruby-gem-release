# Releasing

These instructions describe the reusable release workflow; they do not authorize a release or publication.

## One-Time Setup

Add a caller workflow as shown in [README.md](README.md), with `contents: write` and `id-token: write`, and create a GitHub environment named `release` in the publishing repository. This repository's manual caller is [`.github/workflows/publish.yml`](.github/workflows/publish.yml), which invokes the reusable workflow in the same checkout. Restrict environment deployment branches and require approval when available. Configure the gem's [RubyGems trusted publisher](https://guides.rubygems.org/trusted-publishing/) with the publishing repository and `release` environment, workflow filename `release.yml`, and workflow repository owner `dblock` and name `ruby-gem-release` when calling from another repository. For a first release, configure a pending trusted publisher. The workflow uses short-lived OIDC credentials, not a stored RubyGems API key.

The GitHub Actions token must be permitted to push fast-forward commits and tags to the default branch. Rulesets with a PR requirement may block it; a dedicated release App bypass can preserve PR enforcement if configured. This repository's ruleset instead allows all writers to push directly while blocking force pushes and deletion; ordinary changes still go through PRs. Actions-token pushes do not trigger ordinary push workflows, so the caller's validation command must run the necessary checks.

## Prepare and Publish

### Releasing This Project

The repository's **Release** workflow is manual only; merges and schedules do not publish. It uses the standard workflow configured in the root Rakefile with Ruby 4.0, releasing the current version and preparing the next patch version afterward. The `dry-run` input defaults to `true`.

Before the first publication, configure RubyGems Trusted Publishing for owner `dblock`, repository `ruby-gem-release`, executing workflow `release.yml`, and environment `release`. Leave the optional Workflow Repository fields blank because both workflows live in this repository; `publish.yml` is the dispatch entry point, not the OIDC job workflow. The existing GitHub environment is not proof that RubyGems trusts the caller. For an unpublished gem, use a pending trusted publisher.

Set the non-secret repository variable `RUBYGEMS_OWNER_ID` to the numeric RubyGems account ID shown on the Pending Trusted Publishers page. The caller passes it as `rubygems-owner`, binding the short-lived key to the account whose pending publisher will create the gem. This variable is not an API key and does not replace a pending trusted publisher.

The first failed release authenticated but RubyGems rejected the upload because the owner assertion was absent. The current credentials action does not accept an owner input, so owner-bound exchanges use [`RubyGemsCredentials`](docs/workflow/ruby_gems_credentials.md). With no owner input, existing-gem releases retain the credentials action. No registry credentials or trusted publisher are configured by adding the workflow.

Exercise the workflow from `master` without remote writes:

```sh
gh workflow run publish.yml --ref master -f dry-run=true
```

Only after explicit release authorization, successful validation, and Trusted Publishing setup, dispatch a publishing run:

```sh
gh workflow run publish.yml --ref master -f dry-run=false
```

The Actions token can make fast-forward release and next-version pushes under the existing ruleset, which blocks force pushes and branch deletion. The `release` environment currently has no required reviewer or deployment-branch policy; the reusable workflow still enforces the default branch for publishing runs. Configure stronger environment protection if needed before dispatch.

### Releasing a Consumer Project

Review the changes and dispatch the caller workflow on the current default branch. It reads the initial numeric `MAJOR.MINOR.PATCH` version from the gemspec, then resolves the release version after preparation; an optional version input asserts that prepared value rather than overriding it. Approve the `release` environment if required. Defaults invoke the preparation callback, `bundle exec rake`, the publication callback, and the `after_release` callback. Install [`Workflow::RubyGem`](docs/workflow/ruby_gem.md) as shown in [README.md](README.md#usage), or configure version, changelog, package, and Git operations explicitly using [Detailed Usage](docs/usage.md#custom-callbacks). Custom `prepare`, `publish`, and `bump` commands replace those defaults and own their phase's operations. The publication callback commits changes, builds once, verifies the artifact, creates a local tag and recovery bundle, publishes to RubyGems, pushes the commit and tag atomically, and creates a GitHub Release. Git checks the default branch before publication and again before pushing. The next-version callback changes files, commits them, and pushes only that commit.

The workflow captures `RELEASE_PREVIOUS_VERSION` from the gemspec and `RELEASE_DATE` once before preparation. It sets `RELEASE_VERSION` from the prepared gemspec afterward and rejects a mismatch with optional `INPUT_VERSION`. Lifecycle tasks read those environment values directly; invoke `bundle exec rake release:before_release` or `bundle exec rake release:after_release` without task arguments. Existing keyword-argument callbacks must be migrated to accept the release context described in the README. Manual task installation does not configure a version strategy; construct a local `RubyGemRelease::Version::RubyConstant` as shown in [Detailed Usage](docs/usage.md#custom-callbacks). The standard workflow accepts that object through `version:`.

For a non-publishing integration check, set `dry-run: true` in the caller. The workflow skips RubyGems authentication but invokes every callback. The supplied classes honor `release.dry_run?`, performing local commits, builds, and tags without package uploads, remote Git pushes, or GitHub Release creation. Custom commands and callback code must themselves honor dry runs; never use untrusted commands or workflow inputs.

## Verify and Recover

The `publish` input replaces the former `github-release` command and now invokes the entire publication callback. [`GitHubRelease`](docs/hosting/github_release.md) attaches the exact gem through `package:` after the remote tag push. To disable only GitHub Release creation, set `hosting: nil` in the standard workflow or omit `github.publish!` from manual callbacks, not the publication callback. A custom recovery command must not republish the gem or replace its tag.

Verify the version on RubyGems, the tag's commit, the GitHub Release and attached gem, and the next development version on the default branch. Never overwrite published versions or move release tags.

Publication precedes the atomic commit/tag push, so a concurrent branch update or network failure can leave a published gem without a remote tag. Before retrying any failed or timed-out upload, check RubyGems: the server may have accepted it. If the gem was published, do not rerun the full workflow. Recover the exact release commit from the run logs and the preserved artifact, reconcile concurrent changes without rewriting history, and push the matching commit and tag only after verifying their identity. If the tag exists but the GitHub Release is missing, create it from that tag and attach the preserved artifact. If the release succeeded but the bump failed, update only the missing next-version commit after verifying the current branch and published version.

The workflow uploads available `release.gem`, `release.json`, and `release.bundle` files after the publication callback, even when it fails, with 30-day retention. Runner loss during that callback can prevent preservation; download available artifacts promptly. Fetch the original commit and tag from the bundle, inspect them, and compare the preserved gem and digest with the publication before completing recovery. A new `Package::RubyGem` with the recovered directory can reopen the exact archive without rebuilding. If the default branch advanced, coordinate recovery rather than moving its history or tagging another commit.
