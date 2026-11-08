# GitHub Actions Release Workflow

Reference for [`.github/workflows/release.yml`](../../.github/workflows/release.yml), invoked with `workflow_call`. See [Usage](../../README.md#usage) for a caller example and [Detailed Usage](../usage.md#configuration) for customization. See [RELEASING.md](../../RELEASING.md#one-time-setup) for branch permissions. Trusted Publishing is required setup in [Usage](../../README.md#3-enable-trusted-publishing).

For a step-based interface with caller-owned job settings, see the [Composite Action](action.md). Both interfaces invoke the same Ruby release tasks; the reusable workflow keeps its own runner, environment, permissions contract, and concurrency group.

## Inputs

Set these under the calling job's `with:` mapping. Only `ruby-version` is required.

| Input            | Type   | Default                                        | Behavior                                                                                                                               |
| ---              | ---    | ---                                            | ---                                                                                                                                    |
| `ruby-version`   | String | Required                                       | Ruby version used for validation and building.                                                                                         |
| `version`        | String | Empty                                          | Selected numeric `MAJOR.MINOR.PATCH` release version, without leading zeros. Overrides the checked-in version in standard preparation. |
| `gemspec`        | String | Empty                                          | Specification path, defaulting to the only root gemspec. Missing or ambiguous specifications fail.                                     |
| `rubygems-owner` | String | Empty                                          | Numeric RubyGems account ID required for a new gem's pending trusted publisher to create it.                                           |
| `timezone`       | String | `UTC`                                          | Installed timezone identifier for the release calendar date and Git timestamp offsets.                                                 |
| `prepare`        | String | `bundle exec rake release:before_release`      | Prepare release files before version resolution and validation.                                                                        |
| `validate`       | String | `bundle exec rake`                             | Validate prepared release files before publication.                                                                                    |
| `publish`        | String | `bundle exec rake release:publish`             | Commit, build, tag, publish to RubyGems, push atomically, and create a GitHub Release through the configured callback.                 |
| `bump`           | String | `bundle exec rake release:after_release`       | Prepare, commit, and push the next development iteration through the configured callback.                                              |
| `git-user-name`  | String | `github-actions[bot]`                          | Checkout-local author name for release and next development iteration commits.                                                         |
| `git-user-email` | String | `github-actions[bot]@users.noreply.github.com` | Checkout-local author email for release and next development iteration commits.                                                        |

Identity values must be nonempty and contain no line breaks. They change commit attribution, not authentication or push permissions.

### Release Version

Set `version: '1.2.3'` under `with:` to select a release version instead of the one checked in. The standard workflow calls the configured version object's `set!` method before preparing the changelog; an empty input leaves the checked-in version unchanged. The release commit includes the version and changelog changes, and the next development iteration increments from the selected version. The initial gemspec version and captured date remain available to callbacks.

Expose a string `version` input in the caller's `workflow_dispatch` form and forward it with `version: ${{ inputs.version }}`. You can then choose it in GitHub's form or run `gh workflow run release.yml -f version=1.2.3`. No release is performed by adding this input.

This changes the former assertion-only behavior. Custom preparation commands and callbacks retain control and must honor the selection; resolution rejects a mismatched prepared gemspec before publication. Custom version objects must implement `set!` when selecting a version. The former `RubyConstant#set` API is removed without an alias; use `set!`. Upgrade the gem and pinned interface together when adopting the new behavior.

### Timezone

Starting with version `0.3.0`, set `timezone: America/New_York` under `with:` to use Eastern Time, including daylight saving changes. Upgrade the gem and pinned workflow or action together before adding this input; earlier release tags do not expose it. UTC remains the default.

The interfaces set `TZ` and capture the local calendar date once as `RELEASE_DATE`, preserving it across callbacks even if the release crosses midnight. Git commits retain their actual creation times with offsets in the selected timezone. GitHub and RubyGems generate their own publication timestamps; this input does not change those service timestamps.

Identifiers must resolve to files under the runner's `/usr/share/zoneinfo` directory. Unknown identifiers, empty values, fixed-offset strings, and traversal paths fail before release preparation or publication. Use a named timezone rather than a fixed offset so daylight saving changes are handled correctly.

The `publish` input replaces the former `github-release` input and controls the whole publication sequence. To disable only GitHub Release creation, set `hosting: nil` in the standard workflow or omit `github.publish!` from manual callbacks rather than disabling `publish`.

## Permissions and Authentication

Once the repository and gem owners complete setup, collaborators with write access can [dispatch the release workflow](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow), including in personal repositories. They do not need repository admin access, RubyGems ownership, or their own RubyGems API key. Dispatch permission is not publication approval: with [required maintainer reviewers](../../RELEASING.md#maintainer-approved-publication), publication remains blocked until a designated maintainer approves the `release` environment.

Environments do not provide a workflow-dispatch allow list, and creating one without protection rules does not restrict release access.

For a brand-new gem, register a pending trusted publisher and set `rubygems-owner` to the numeric account ID shown on that page. The [owner-aware helper](../workflow/ruby_gems_credentials.md) requests a GitHub OIDC token for audience `rubygems.org`, exchanges it with the owner assertion, masks both credentials, and exports the short-lived key for publication. The current credentials action lacks this owner input; existing-gem releases with no owner specified continue to use it.

The caller needs `contents: write` for Git pushes and GitHub Releases, and `id-token: write` for RubyGems Trusted Publishing. Configure the `release` environment and RubyGems trusted publisher as described in [Usage](../../README.md#3-enable-trusted-publishing). No stored RubyGems API key is required.

The workflow uses the GitHub Actions token as `GH_TOKEN` during publication. Branch rules must permit its fast-forward pushes while retaining force-push and deletion restrictions.

## Execution

After `ruby/setup-ruby` installs dependencies, context capture requires a clean checkout before preparation: tracked/index changes and untracked non-ignored files fail with actionable paths. Ignored Bundler output is allowed; tracked dependency artifacts are not. Resolving the prepared version stages the trusted `prepare` command's outputs and records the index tree before validation. The publication callback refuses later working tree or index changes rather than staging unrelated files. Custom commands own their operations; wrap custom next development iteration edits in `git.stage_changes!` as shown in [Detailed Usage](../usage.md#custom-callbacks).

The job runs on `ubuntu-latest` in the `release` environment. It checks out full history, sets up Ruby with Bundler caching, captures release context, runs `prepare`, resolves the prepared version, runs `validate`, authenticates to RubyGems, runs `publish`, uploads available recovery artifacts, then runs `bump`. Ordinary failures prevent later callback phases; artifact uploading is attempted even after failure.

Releases must run from the default branch at its current remote commit. Git checks the branch again before publication and pushing, rejects existing tags, and pushes the release commit and tag atomically. Concurrency is grouped by repository without canceling a running release.

## Command Environment

Commands run through `bash -euo pipefail`. Overrides replace the corresponding phase and must perform its required operations; callback registration alone does not cause an overridden command to invoke a task.

| Variable                          | Availability     | Meaning                                                              |
| ---                               | ---              | ---                                                                  |
| `INPUT_VERSION`                   | All phases       | Optional selected release version.                                   |
| `INPUT_GEMSPEC`                   | All phases       | Optional gemspec input.                                              |
| `RUBYGEMS_OWNER`                  | All phases       | Optional numeric RubyGems account ID for owner-bound authentication. |
| `GEMSPEC`                         | After capture    | Selected absolute gemspec path.                                      |
| `RELEASE_PREVIOUS_VERSION`        | After capture    | Initial gemspec version, retained across callbacks.                  |
| `RELEASE_DATE`                    | After capture    | Date captured once in the configured timezone, as `YYYY-MM-DD`.      |
| `TZ`                              | All phases       | Configured timezone; defaults to `UTC`.                              |
| `RELEASE_INITIAL_COMMIT`          | After capture    | Checkout commit used for concurrency checks.                         |
| `RELEASE_VERSION`                 | After resolution | Prepared version to publish.                                         |
| `DEFAULT_BRANCH`                  | All phases       | Repository default branch.                                           |
| `GIT_USER_NAME`, `GIT_USER_EMAIL` | All phases       | Configured checkout-local commit identity.                           |
| `GH_TOKEN`                        | Publication      | GitHub Actions token for GitHub Release creation.                    |

GitHub also supplies standard variables such as `GITHUB_REPOSITORY` and `RUNNER_TEMP`. See [`Tasks`](../tasks.md) for callback context semantics and [`Workflow::Context`](../workflow/context.md) for capture and resolution methods.

## Recovery Artifacts

The workflow preserves available `release.gem`, `release.json`, and `release.bundle` files from `RUNNER_TEMP` for 30 days, named `release-gem-VERSION-RUN_ID-RUN_ATTEMPT`. The manifest records the exact artifact checksum; the bundle contains the release commit and tag.

Uploading happens after the publication callback, even if it fails. Runner loss during the callback can prevent preservation. RubyGems publication precedes the atomic push, leaving a recovery window if pushing fails. Verify remote state before retrying; never republish an accepted version or move a release tag. See [RELEASING.md](../../RELEASING.md#verify-and-recover).
