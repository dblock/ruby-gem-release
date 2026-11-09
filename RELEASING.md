# Releasing

These instructions do not authorize publication. Upgrade the gem and pinned workflow or action together; see [UPGRADING.md](UPGRADING.md) for migrations.

## One-Time Setup

Follow [README Usage](README.md#usage) to add a caller with `contents: write` and `id-token: write`, then create a GitHub environment named `release`.

Configure [RubyGems Trusted Publishing](https://guides.rubygems.org/trusted-publishing/) for the publishing repository, executing workflow `release.yml`, and environment `release`. When calling this repository's reusable workflow from another repository, set the separate workflow repository fields to `dblock` and `ruby-gem-release`. For this project's local caller, leave those fields blank: `publish.yml` dispatches the run, but `release.yml` executes the OIDC job.

For a gem's first publication, configure a pending trusted publisher and pass its numeric account ID as `rubygems-owner`. Existing gems normally omit that input. Authentication exports short-lived credentials without writing `~/.gem/credentials`; adding the workflow configures neither registry trust nor credentials.

The Actions token must be allowed to push fast-forward commits and tags. A PR requirement may block it; a separately configured release App bypass can preserve PR enforcement. This repository instead permits direct pushes by all writers while blocking force pushes and deletion; ordinary development still uses PRs. Actions-token pushes do not trigger ordinary push workflows, so release validation must run the necessary checks.

### Maintainer-Approved Publication

Creating an environment alone does not restrict publication. Under **Settings > Environments > release**, configure [environment protection](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments):

- **Required reviewers:** Select maintainers; any one can approve.
- **Prevent self-review:** Enable for two-person approval; disable to let a maintainer dispatch and approve.
- **Administrator bypass:** Disable if approval must always be required.
- **Deployment branches and tags:** Select only the actual default branch (`master` here), with no tag rules.

Availability depends on visibility and plan; verify these controls before relying on them. Other writers can still dispatch, but the protected job waits for approval before running steps or obtaining credentials. Environment rules protect jobs, not the dispatch entry point.

## Prepare and Publish

Both interfaces require the default branch and a clean checkout after dependency installation. Ignore intentional dependency output such as `.bundle/config` or `vendor/bundle`; unexpected tracked, staged, or untracked non-ignored changes fail. Preparation stages trusted edits before testing; publication rejects subsequent changes rather than staging them.

The default manual workflow releases the checked-in version, or honors an explicit `version` input, then increments patch afterward. Semantic workflows select from release history and default to no development bump. Custom commands own their operations and must retain the [documented ordering and guards](docs/usage.md#custom-callbacks).

Validate and build before authorizing a release:

```sh
bundle exec rake
bundle exec rake build
```

### Releasing This Project

The manual **Release** caller is [`.github/workflows/publish.yml`](.github/workflows/publish.yml). Merges and schedules do not publish. It uses Ruby 4.0, the root Rakefile, and `America/New_York` for release dates and Git timestamp offsets.

Verify the existing RubyGems trusted publisher before dispatch. The caller passes the non-secret `RUBYGEMS_OWNER_ID` repository variable when set; this identifies an account, not an API key. Pending publishers need it for first publication.

Only after explicit authorization, successful validation, and confirmed setup:

```sh
gh workflow run publish.yml --ref master
```

Every dispatch requests publication unless validation skips. Required environment reviewers approve before the job starts. After publication, `ReleaseVersion` updates README pins to the released tag while incrementing the development version; these edits belong to the next-development commit, not the release tag.

### Releasing a Consumer Project

Use the [README setup](README.md#usage), dispatch its caller on the default branch, and approve the environment when required. For an explicit version, pass `-f version=1.2.3` to that caller's `gh workflow run` command.

The pipeline captures the initial version and date once, validates, prepares, resolves the selected package, tests, authenticates, publishes, and optionally bumps. Publication commits, builds once, tags and creates a recovery bundle, uploads the exact gem, pushes commit and tag atomically, then creates the hosted release. See [Actions inputs](docs/actions/release.md) for overrides and [Git preparation](docs/source_control/git.md#clean-checkout-and-preparation) for custom edits.

Never invoke publication as a preview. Custom commands execute with release privileges and must be trusted; callers bypassing `release:publish` own authentication.

## Publish the Action to Marketplace

After an authorized release, confirm its tag contains root `action.yml` and matches the gem and GitHub Release. Never move an existing tag to add metadata.

The owner must accept the Marketplace Developer Agreement. Edit the new GitHub Release, select **Publish this Action to the GitHub Marketplace**, choose categories, and save. Follow [GitHub's requirements](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/publish-in-github-marketplace); listing is separate from release creation and is not automated here.

## Verify and Recover

Verify the RubyGems version, tag commit, GitHub Release and attached archive, and next development commit when enabled. Never overwrite published versions or move release tags.

Registry upload precedes the atomic Git push. A concurrent branch update or network failure can leave a published gem without a remote tag. Before retrying any failed or timed-out upload, check RubyGems: the server may have accepted it.

- **Gem published, remote refs missing:** Do not rerun the workflow. Recover the exact release commit and tag from the preserved bundle, verify their identity against the published artifact, reconcile concurrent changes without rewriting history, and push only the missing refs. Coordinate if the default branch advanced.
- **Tag exists, hosted release missing:** Create the GitHub Release from that tag and attach the preserved gem without republishing.
- **Release complete, development bump failed:** Verify the published version and branch, then complete only the missing development iteration.

Actions preserves available `release.gem`, `release.json`, and `release.bundle` files after the publication callback, including on failure, for 30 days. Runner loss during the callback can prevent preservation; download available files promptly. Compare the manifest digest and archive with the publication before completing recovery. A new `Package::RubyGem` using the recovered directory can verify and reopen the archive without rebuilding.

To disable hosted releases intentionally, use `hosting: nil` or omit the hosting call in manual callbacks—not the entire publication callback.
