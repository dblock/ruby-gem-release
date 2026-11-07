# GitHub Actions Release Workflow

Reference for [`.github/workflows/release.yml`](../../.github/workflows/release.yml), invoked with `workflow_call`. See [Usage](../../README.md#usage) for a caller example and [Detailed Usage](../usage.md#configuration) for customization. See [RELEASING.md](../../RELEASING.md#one-time-setup) for branch permissions. Trusted Publishing is required setup in [Usage](../../README.md#3-enable-trusted-publishing).

For a step-based interface with caller-owned job settings, see the [Composite Action](action.md). Both interfaces invoke the same Ruby release tasks; the reusable workflow keeps its own runner, environment, permissions contract, and concurrency group.

## Inputs

Set these under the calling job's `with:` mapping. Only `ruby-version` is required.

| Input            | Type    | Default                                        | Behavior                                                                                                                        |
| ---              | ---     | ---                                            | ---                                                                                                                             |
| `ruby-version`   | String  | Required                                       | Ruby version used for validation and building.                                                                                  |
| `version`        | String  | Empty                                          | Expected numeric `MAJOR.MINOR.PATCH` version, without leading zeros. Must match the prepared gemspec; does not set the version. |
| `gemspec`        | String  | Empty                                          | Specification path, defaulting to the only root gemspec. Missing or ambiguous specifications fail.                              |
| `rubygems-owner` | String  | Empty                                          | Numeric RubyGems account ID required for a new gem's pending trusted publisher to create it.                                    |
| `prepare`        | String  | `bundle exec rake release:before_release`      | Prepare release files before version resolution and validation.                                                                 |
| `validate`       | String  | `bundle exec rake`                             | Validate prepared release files before publication.                                                                             |
| `publish`        | String  | `bundle exec rake release:publish`             | Commit, build, tag, publish to RubyGems, push atomically, and create a GitHub Release through the configured callback.          |
| `bump`           | String  | `bundle exec rake release:after_release`       | Prepare, commit, and push the next development version through the configured callback.                                         |
| `git-user-name`  | String  | `github-actions[bot]`                          | Checkout-local author name for release and next-version commits.                                                                |
| `git-user-email` | String  | `github-actions[bot]@users.noreply.github.com` | Checkout-local author email for release and next-version commits.                                                               |
| `dry-run`        | Boolean | `false`                                        | Exercise local release work without remote writes from the supplied classes.                                                    |

Identity values must be nonempty and contain no line breaks. They change commit attribution, not authentication or push permissions.

The `publish` input replaces the former `github-release` input and controls the whole publication sequence. To disable only GitHub Release creation, set `hosting: nil` in the standard workflow or omit `github.publish!` from manual callbacks rather than disabling `publish`.

## Permissions and Authentication

For a brand-new gem, register a pending trusted publisher and set `rubygems-owner` to the numeric account ID shown on that page. The [owner-aware helper](../workflow/ruby_gems_credentials.md) requests a GitHub OIDC token for audience `rubygems.org`, exchanges it with the owner assertion, masks both credentials, and exports the short-lived key for publication. The current credentials action lacks this owner input; existing-gem releases with no owner specified continue to use it. Both authentication paths are skipped in dry runs.

The caller needs `contents: write` for Git pushes and GitHub Releases, and `id-token: write` for RubyGems Trusted Publishing. Configure the `release` environment and RubyGems trusted publisher as described in [Usage](../../README.md#3-enable-trusted-publishing). No stored RubyGems API key is required.

The workflow uses the GitHub Actions token as `GH_TOKEN` during publication. Branch rules must permit its fast-forward pushes while retaining force-push and deletion restrictions.

## Execution

The job runs on `ubuntu-latest` in the `release` environment. It checks out full history, sets up Ruby with Bundler caching, captures release context, runs `prepare`, resolves the prepared version, runs `validate`, authenticates to RubyGems, runs `publish`, uploads available recovery artifacts, then runs `bump`. Ordinary failures prevent later callback phases; artifact uploading is attempted even after failure.

Releases must run from the default branch at its current remote commit. Git checks the branch again before publication and pushing, rejects existing tags, and pushes the release commit and tag atomically. Concurrency is grouped by repository without canceling a running release.

## Command Environment

Commands run through `bash -euo pipefail`. Overrides replace the corresponding phase and must perform its required operations; callback registration alone does not cause an overridden command to invoke a task.

| Variable                          | Availability     | Meaning                                                                 |
| ---                               | ---              | ---                                                                     |
| `INPUT_VERSION`                   | All phases       | Optional expected-version input.                                        |
| `INPUT_GEMSPEC`                   | All phases       | Optional gemspec input.                                                 |
| `RUBYGEMS_OWNER`                  | All phases       | Optional numeric RubyGems account ID for owner-bound authentication.    |
| `GEMSPEC`                         | After capture    | Selected absolute gemspec path.                                         |
| `RELEASE_PREVIOUS_VERSION`        | After capture    | Initial gemspec version, retained across callbacks.                     |
| `RELEASE_DATE`                    | After capture    | Date captured once in UTC, as `YYYY-MM-DD`.                             |
| `RELEASE_INITIAL_COMMIT`          | After capture    | Checkout commit used for concurrency checks.                            |
| `RELEASE_VERSION`                 | After resolution | Prepared version to publish.                                            |
| `DRY_RUN`                         | All phases       | `true` or `false`; lifecycle tasks carry this into the release context. |
| `DEFAULT_BRANCH`                  | All phases       | Repository default branch.                                              |
| `GIT_USER_NAME`, `GIT_USER_EMAIL` | All phases       | Configured checkout-local commit identity.                              |
| `GH_TOKEN`                        | Publication      | GitHub Actions token for GitHub Release creation.                       |

GitHub also supplies standard variables such as `GITHUB_REPOSITORY` and `RUNNER_TEMP`. See [`Tasks`](../tasks.md) for callback context semantics and [`Workflow::Context`](../workflow/context.md) for capture and resolution methods.

## Dry Runs

With `dry-run: true`, RubyGems authentication is skipped, but all callback commands still run. The supplied package, Git, and hosting classes honor `release.dry_run?`: commits, builds, and local tags run; package uploads, Git pushes, and GitHub Release creation do not. Dry runs allow non-default-branch checkouts, but still fetch the remote branch and tags.

Custom commands and callbacks execute with workflow privileges and must be trusted and dry-run-aware; arbitrary code is not constrained by this flag.

## Recovery Artifacts

The workflow preserves available `release.gem`, `release.json`, and `release.bundle` files from `RUNNER_TEMP` for 30 days, named `release-gem-VERSION-RUN_ID-RUN_ATTEMPT`. The manifest records the exact artifact checksum; the bundle contains the release commit and tag.

Uploading happens after the publication callback, even if it fails. Runner loss during the callback can prevent preservation. RubyGems publication precedes the atomic push, leaving a recovery window if pushing fails. Verify remote state before retrying; never republish an accepted version or move a release tag. See [RELEASING.md](../../RELEASING.md#verify-and-recover).
