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
| `validate`       | String | `bundle exec rake release:validate`            | Check release preconditions before edits; exit nonzero on failure.                                                                     |
| `prepare`        | String | `bundle exec rake release:prepare`             | Prepare release files before version resolution and testing.                                                                           |
| `test`           | String | `bundle exec rake`                             | Test prepared release files before publication.                                                                                        |
| `publish`        | String | `bundle exec rake release:publish`             | Commit, build, tag, publish to RubyGems, push atomically, and create a GitHub Release through the configured callback.                 |
| `bump`           | String | `bundle exec rake release:bump`                | Prepare, commit, and push the next development iteration through the configured callback.                                              |
| `success`        | String | `bundle exec rake release:success`             | Run after publication and the next development iteration succeed.                                                                      |
| `failure`        | String | `bundle exec rake release:failure`             | Run after a release job failure, after Ruby setup.                                                                                     |
| `git-user-name`  | String | `github-actions[bot]`                          | Checkout-local author name for release and next development iteration commits.                                                         |
| `git-user-email` | String | `github-actions[bot]@users.noreply.github.com` | Checkout-local author email for release and next development iteration commits.                                                        |

Identity values must be nonempty and contain no line breaks. They change commit attribution, not authentication or push permissions.

### Release Validation

Validation runs after context capture, before preparation edits. Empty pending notes fail unless the selected release already has a changelog heading, allowing repetition. Malformed content also fails. With no changelog, validation passes. Custom changelog objects implement `pending?` and `released?(version)` or supply a `validate:` callback.

A custom `validate` command must exit nonzero on invalid state; normal completion succeeds. Ruby callbacks raise on failure, and returning `false` also fails. No output protocol is required.

A validation error fails the job, stops downstream release operations, and invokes failure handling after successful Ruby setup. There is no successful no-release outcome or `skipped` output.

Move former post-preparation `validate:` test overrides to `test:`. Replace old decision-output commands with failing exit statuses, and upgrade the gem and pinned interface together.

### Release Version

Set `version: '1.2.3'` under `with:` to select a release version instead of the one checked in. The standard workflow calls the configured version object's `set!` method before preparing the changelog; an empty input leaves the checked-in version unchanged. The release commit includes the version and changelog changes, and the next development iteration increments from the selected version. The initial gemspec version and captured date remain available to callbacks.

Expose a string `version` input in the caller's `workflow_dispatch` form and forward it with `version: ${{ inputs.version }}`. You can then choose it in GitHub's form or run `gh workflow run release.yml -f version=1.2.3`. No release is performed by adding this input.

This changes the former assertion-only behavior. Custom preparation commands and callbacks retain control and must honor the selection; resolution rejects a mismatched prepared gemspec before publication. Custom version objects must implement `set!` when selecting a version. The former `RubyConstant#set` API is removed without an alias; use `set!`. Upgrade the gem and pinned interface together when adopting the new behavior.

### Timezone

Starting with version `0.3.0`, set `timezone: America/New_York` under `with:` to use Eastern Time, including daylight saving changes. Upgrade the gem and pinned workflow or action together before adding this input; earlier release tags do not expose it. UTC remains the default.

The interfaces set `TZ` and capture the local calendar date once as `RELEASE_DATE`, preserving it across callbacks even if the release crosses midnight. Git commits retain their actual creation times with offsets in the selected timezone. GitHub and RubyGems generate their own publication timestamps; this input does not change those service timestamps.

Identifiers must resolve to files under the runner's `/usr/share/zoneinfo` directory. Unknown identifiers, empty values, fixed-offset strings, and traversal paths fail before release preparation or publication. Use a named timezone rather than a fixed offset so daylight saving changes are handled correctly.

The `publish` input replaces the former `github-release` input and controls the whole publication sequence. To disable only GitHub Release creation, set `hosting: nil` in the standard workflow or omit `github.publish!` from manual callbacks rather than disabling `publish`.

### Success and Failure Callbacks

The `success` command runs after the publication and next development iteration phases succeed. The `failure` command runs after a failed phase once Ruby setup has completed; its callback receives a `RubyGemRelease::ReleaseFailure` with the failed phase, an exception captured from a Ruby task when available, and an execution context whose release value is optional. Failures reported only by GitHub Actions have no exception object. Both default to optional Rake callbacks and are no-ops when none are registered. Failure before Ruby setup or a job blocked by environment protection cannot invoke the callback.

## Permissions and Authentication

Once the repository and gem owners complete setup, collaborators with write access can [dispatch the release workflow](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow), including in personal repositories. They do not need repository admin access, RubyGems ownership, or their own RubyGems API key. Dispatch permission is not publication approval: with [required maintainer reviewers](../../RELEASING.md#maintainer-approved-publication), publication remains blocked until a designated maintainer approves the `release` environment.

Environments do not provide a workflow-dispatch allow list, and creating one without protection rules does not restrict release access.

Authentication belongs to `release:publish`, which invokes the configured destination's authentication hook before its publication callback. Neither YAML interface contains a registry-specific authentication step or condition. The RubyGems destination uses [`RubyGemsCredentials`](../workflow/ruby_gems_credentials.md), requesting a GitHub OIDC token for audience `rubygems.org`, exchanging it, masking both credentials, and exporting the short-lived key for publication. For a brand-new gem, register a pending trusted publisher and set `rubygems-owner` to the numeric account ID shown on that page; the helper includes that owner assertion. For existing gems, omit the input and the exchange omits the owner field.

Authentication exports `RUBYGEMS_API_KEY`, `BUNDLE_GEM__PUSH_KEY`, and `GEM_HOST_API_KEY`; it does not create or modify `~/.gem/credentials`. Custom publication commands must inherit these variables rather than assume a credentials file or named key exists. See the [custom publication contract](../workflow/ruby_gems_credentials.md#custom-publication-commands).

The caller needs `contents: write` for Git and hosting and `id-token: write` for RubyGems Trusted Publishing. Configure the `release` environment and publisher as described in [Usage](../../README.md#3-enable-trusted-publishing). No stored RubyGems API key is required.

The base destination's authentication hook retains preconfigured credentials. Custom destinations can override it without adding or changing YAML steps; prepared-version checks also use the configured destination. A `publish` command override that bypasses `release:publish` must own authentication as well as publication. See [Registry Destinations](../destination.md).

The workflow supplies `GH_TOKEN` during capture and publication. Branch rules must permit fast-forward pushes while retaining force-push and deletion restrictions.

## Execution

After `ruby/setup-ruby` installs dependencies, context capture requires a clean checkout before preparation: tracked/index changes and untracked non-ignored files fail with actionable paths. Ignored Bundler output is allowed; tracked dependency artifacts are not. Resolving the prepared version stages the trusted `prepare` command's outputs and records the index tree before validation. The publication callback refuses later working tree or index changes rather than staging unrelated files. Custom commands own their operations; wrap custom next development iteration edits in `git.stage_changes!` as shown in [Detailed Usage](../usage.md#custom-callbacks).

The job runs on `ubuntu-latest` in the `release` environment. After full checkout and Ruby setup, capture uses the current checkout and inputs. Commands always run and own their idempotence; there is no cross-run artifact discovery or state restoration. A checkpoint commits, builds, and tags locally; artifact preservation must succeed before `publish` and `bump`. Failures prevent later phases.

New releases require the current default-branch commit. Recovery can restore an earlier verified release without rewinding remote descendants. Git rejects conflicting tags and unrelated advancement. Concurrency is grouped by repository without canceling a running release.

## Command Environment

Commands run through `bash -euo pipefail`. Overrides replace the corresponding phase and must perform its required operations; callback registration alone does not cause an overridden command to invoke a task.

| Variable                          | Availability     | Meaning                                                                 |
| ---                               | ---              | ---                                                                     |
| `INPUT_VERSION`                   | All phases       | Optional selected release version.                                      |
| `RELEASE_FAILURE_PHASE`           | Failure callback | Failed workflow step when available.                                    |
| `RELEASE_STEP_ID`                 | Commands         | Current enclosing Actions step ID.                                      |
| `RELEASE_STEPS`                   | Commands         | JSON snapshot of previously observed Actions steps.                     |
| `RELEASE_STATE`                   | After capture    | Private invocation-specific state file for callback data.               |
| `RELEASE_DIRECTORY`               | After capture    | Provider directory; maps to `RUNNER_TEMP` on Actions.                   |
| `RELEASE_AUTHENTICATION`          | After resolution | Destination authentication strategy, or empty for existing credentials. |
| `INPUT_GEMSPEC`                   | All phases       | Optional gemspec input.                                                 |
| `RUBYGEMS_OWNER`                  | All phases       | Optional numeric RubyGems account ID for owner-bound authentication.    |
| `GEMSPEC`                         | After capture    | Selected absolute gemspec path.                                         |
| `RELEASE_PREVIOUS_VERSION`        | After capture    | Initial gemspec version, retained across callbacks.                     |
| `RELEASE_DATE`                    | After capture    | Date captured once in the configured timezone, as `YYYY-MM-DD`.         |
| `TZ`                              | All phases       | Configured timezone; defaults to `UTC`.                                 |
| `RELEASE_INITIAL_COMMIT`          | After capture    | Checkout commit used for concurrency checks.                            |
| `RELEASE_VERSION`                 | After resolution | Prepared version to publish.                                            |
| `DEFAULT_BRANCH`                  | All phases       | Repository default branch.                                              |
| `GIT_USER_NAME`, `GIT_USER_EMAIL` | All phases       | Configured checkout-local commit identity.                              |
| `GH_TOKEN`                        | Capture/publish  | GitHub Actions token for artifact discovery and hosted releases.        |

GitHub also supplies standard variables such as `GITHUB_REPOSITORY` and `RUNNER_TEMP`. See [Execution Context](../execution_context.md) for step, run, and state semantics, [`Tasks`](../tasks.md) for callbacks, and [`Workflow::Environment`](../workflow/environment.md) for capture and resolution methods.

## Recovery Artifacts

The workflow requires `release.gem`, its name/version/digest manifest `release.json`, and `release.bundle` to be uploaded before publication, retained for 30 days under `release-gem-VERSION-RUN_ID-RUN_ATTEMPT`. These support manual inspection, not automatic restoration. See [RELEASING.md](../../RELEASING.md#verify-and-recover).
