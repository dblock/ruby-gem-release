# Releasing

These instructions do not authorize publication. Upgrade the gem and the pinned workflow or action together; see [UPGRADING.md](UPGRADING.md).

## One-Time Setup

1. Add a caller workflow, create the `release` environment, and configure a RubyGems trusted publisher, as described in [README Usage](README.md#usage).
2. Protect the environment as described in [Maintainer-Approved Publication](#maintainer-approved-publication).
3. Allow the Actions token to push fast-forward commits and tags.

For this project's own trusted publisher, leave the workflow repository fields blank: `publish.yml` starts the run, but the OIDC job runs in this repository's `release.yml`. Other repositories set them to `dblock` and `ruby-gem-release`. See [Permissions and Authentication](docs/actions/release.md#permissions-and-authentication) for first-release owner IDs and exported credentials.

A branch rule that requires PRs blocks the Actions token; a bypass for a separate release App keeps PR enforcement. This repository lets all writers push directly but blocks force pushes and deletion; ordinary development still uses PRs. Pushes by the Actions token do not trigger other push workflows, so the release run must run every check you need.

### Maintainer-Approved Publication

An environment alone does not restrict publication. Under **Settings > Environments > release**, configure [environment protection](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments):

- **Required reviewers:** Select maintainers; any one can approve.
- **Prevent self-review:** Enable to require a second person; disable to let a maintainer approve their own dispatch.
- **Administrator bypass:** Disable if approval must always be required.
- **Deployment branches and tags:** Allow only the default branch (`master` here), with no tag rules.

Availability depends on visibility and plan, so confirm these controls exist. Any writer can still dispatch, but the job waits for approval before it runs or gets credentials.

## Prepare and Publish

Releases run from the default branch with a clean checkout; see [Execution](docs/actions/release.md#execution) for the checks and step order. The [manual workflow](docs/workflow/ruby_gem.md) releases the checked-in version or the `version` input, then bumps patch. The [semantic workflow](docs/workflow/semantic_ruby_gem.md) picks the version from release history and does not bump by default. Custom commands must keep the [documented ordering and guards](docs/usage.md#custom-callbacks).

Test and build before you authorize a release:

```sh
bundle exec rake
bundle exec rake build
```

### Releasing This Project

The manual **Release** workflow is [`.github/workflows/publish.yml`](.github/workflows/publish.yml); the [self-release walkthrough](examples/self_release/README.md) explains its configuration. Merges and schedules never publish.

1. Check the trusted publisher with a [dry run](docs/actions/release.md#dry-run), which exchanges credentials without releasing: `gh workflow run publish.yml --ref master -f dry-run=true`.
2. Only with explicit authorization, passing validation, and confirmed setup, dispatch the release. A required reviewer then approves the `release` environment.

```sh
gh workflow run publish.yml --ref master
```

Every dispatch tries to publish; nothing to release fails validation. The `RUBYGEMS_OWNER_ID` repository variable, when set, is passed as `rubygems-owner`. It is an account ID, not an API key, and only pending publishers need it.

### Releasing a Consumer Project

Follow [Make a Release](README.md#4-make-a-release): dispatch the caller on the default branch and approve the environment if required. For a specific version, add `-f version=1.2.3` to `gh workflow run`. See [Actions inputs](docs/actions/release.md) for options.

Never run publication as a preview. Custom commands run with release privileges and must be trusted. Callers that skip `release:publish` handle authentication themselves.

## Publish the Action to Marketplace

Marketplace listing is manual and separate from the release.

1. Confirm the new tag contains root `action.yml` and matches the gem and GitHub Release. Never move a tag to add metadata.
2. Make sure the owner has accepted the Marketplace Developer Agreement.
3. Edit the GitHub Release, select **Publish this Action to the GitHub Marketplace**, choose categories, and save.

See [GitHub's requirements](https://docs.github.com/en/actions/how-tos/create-and-publish-actions/publish-in-github-marketplace).

## Verify and Recover

Check the RubyGems version, the tag commit, the GitHub Release and its gem, and the next development commit if enabled. Never overwrite a published version or move a release tag.

To recover, rerun with the same source commit and inputs, including the release date. Every release step is idempotent: it finishes only what is missing. There are no recovery flags, artifact discovery, restored state, or completion journal, and a new run never picks up an older unfinished release. On a rerun:

- **Build** produces the same gem. `SOURCE_DATE_EPOCH` defaults to the committer time of the source commit and sets the gemspec date and archive timestamps. You keep toolchains, gemspecs, generated files, and signing inputs stable.
- **RubyGems** accepts an existing version only if its SHA256 matches.
- **Git** reuses matching commits, never moves tags, and never rewinds newer remote commits.
- **Bump** calculates from the release version, so it never bumps twice.
- **GitHub Release** replaces differing metadata, changelog notes, and assets. GitHub-generated notes, used when there are no notes, are kept.

Before publishing, the workflow uploads [recovery artifacts](docs/actions/release.md#recovery-artifacts) for manual inspection; nothing restores them. Investigate conflicting checksums or tags and unexpected branch changes. If the default branch moved during publication, follow [the manual recovery](docs/actions/release.md#default-branch-advanced-during-publication).

Custom commands and callbacks must be idempotent too. Notifications need a receiver-side check or a stable key such as `"release/example/1.2.3/success"`, never a run ID; otherwise they may be sent twice. Reruns verify the gem, Git, hosting, and bump, not your callbacks.

To skip hosted releases, use `hosting: nil` or omit the hosting call in manual callbacks, not the whole publication callback.
