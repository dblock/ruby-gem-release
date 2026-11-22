# GitHub Actions Release Workflow

Reference for the reusable workflow [`.github/workflows/release.yml`](../../.github/workflows/release.yml). For setup, including required [Trusted Publishing](../../README.md#3-enable-trusted-publishing), see [Usage](../../README.md#usage). For customization, see [Detailed Usage](../usage.md#configuration); for branch permissions, see [RELEASING.md](../../RELEASING.md#one-time-setup).

To control the runner, environment, permissions, and concurrency yourself, use the [Composite Action](action.md). Both run the same Ruby release tasks.

This workflow pins every action it uses to a commit SHA. RubyGems Trusted Publishing accepts any ref of this repository, so pin your `uses:` line to a release tag's commit, with the tag in a comment, such as `dblock/ruby-gem-release/.github/workflows/release.yml@<commit> # v0.8.0`. That locks both this workflow and the actions it runs with release credentials.

## Inputs

Set these under `with:`. Only `ruby-version` is required.

| Input               | Type    | Default                                        | Behavior                                                                                                                                  |
| ---                 | ---     | ---                                            | ---                                                                                                                                       |
| `ruby-version`      | String  | Required                                       | Ruby version used to validate and build.                                                                                                  |
| `version`           | String  | Empty                                          | Release version, as `MAJOR.MINOR.PATCH` without leading zeros. Overrides the checked-in version. See [Release Version](#release-version). |
| `gemspec`           | String  | Empty                                          | Gemspec path. Defaults to the only gemspec in the root; fails if there are none or several.                                               |
| `gemfile`           | String  | `Gemfile`                                      | Gemfile for Bundler and every release step. See [Release Gemfile](#release-gemfile).                                                      |
| `rubygems-owner`    | String  | Empty                                          | Your numeric RubyGems account ID. Required only for a gem's first release.                                                                |
| `timezone`          | String  | `UTC`                                          | Timezone for the release date and Git timestamps. See [Timezone](#timezone).                                                              |
| `prepare-artifacts` | String  | Empty                                          | Trusted command that prepares explicitly chosen input archives after setup, before capture.                                               |
| `artifacts`         | String  | Empty                                          | Extra paths to preserve before publication, one per line, in addition to the defaults.                                                    |
| `validate`          | String  | `bundle exec rake release:validate`            | Checks that a release can start, before any edits. Must exit nonzero on failure.                                                          |
| `prepare`           | String  | `bundle exec rake release:prepare`             | Updates release files before tests.                                                                                                       |
| `test`              | String  | `bundle exec rake`                             | Tests the prepared release before publication.                                                                                            |
| `publish`           | String  | `bundle exec rake release:publish`             | Commits, builds, tags, publishes to RubyGems, pushes, and creates a GitHub Release.                                                       |
| `bump`              | String  | `bundle exec rake release:bump`                | Prepares, commits, and pushes the next development version.                                                                               |
| `success`           | String  | `bundle exec rake release:success`             | Runs after publication and the version bump succeed.                                                                                      |
| `failure`           | String  | `bundle exec rake release:failure`             | Runs after a failure, once Ruby is set up.                                                                                                |
| `git-user-name`     | String  | `github-actions[bot]`                          | Author name for release and version bump commits.                                                                                         |
| `git-user-email`    | String  | `github-actions[bot]@users.noreply.github.com` | Author email for release and version bump commits.                                                                                        |
| `dry-run`           | Boolean | `false`                                        | Only checks prerequisites. Edits, pushes, and publishes nothing. See [Dry Run](#dry-run).                                                 |

"Capture" is the first release step. It records the checkout, gemspec, version, and date for later steps. The author name and email must be nonempty single lines; they affect commit authorship only, not authentication.

### Release Prerequisites

Every release first runs `bundle exec rake release:workflow:preflight`, so missing permissions fail before any edit, push, or publication. It checks:

- **Trusted Publishing:** it exchanges the job's OIDC token at RubyGems exactly as publication does, with `rubygems-owner` when set. Success means the caller granted `id-token: write` and a trusted publisher matches the repository, workflow, and environment. The job prints the token claims and credential scopes, or the claims RubyGems rejected. The credential is masked, expires in 15 minutes, and is never used.
- **Push access:** `git push --dry-run` to the default branch fails without `contents: write`. It sends nothing.
- **Repository rules:** it reads the [rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) for the default branch and the `vVERSION` tag. Branch rules that require pull requests, status checks, signed commits, deployments, or a merge queue, or that restrict updates, fail the check. So do tag rules that restrict creation or require signatures. Rules the token can bypass are fine.

The check cannot confirm the publisher belongs to this gem, or that RubyGems will accept the package, because RubyGems doesn't expose that. Classic branch protection needs admin access to read, so it only produces a warning.

### Dry Run

Set `dry-run: true` to run only the [prerequisite checks](#release-prerequisites). A separate `preflight` job replaces the `release` job, in the same `release` environment, so required reviewers still approve it. It never edits, commits, tags, pushes, builds, or publishes. It also checks that the checkout is clean after Ruby setup, so a dry run catches setup output such as `vendor/bundle` that `.gitignore` is missing. To dispatch dry runs, add a boolean input:

```yaml
on:
  workflow_dispatch:
    inputs:
      dry-run:
        description: Check release prerequisites without releasing.
        type: boolean
        default: false

jobs:
  release:
    uses: dblock/ruby-gem-release/.github/workflows/release.yml@v0.9.0
    with:
      ruby-version: '3.3'
      dry-run: ${{ inputs.dry-run }}
```

Then run `gh workflow run release.yml -f dry-run=true`.

### Release Validation

Validation runs after capture, before any edits. It fails if the changelog is malformed, or has no pending notes and no heading for this version. An existing heading lets you rerun a release. Without a changelog, validation passes. Custom changelog classes implement `pending?` and `released?(version)`, or you supply a `validate:` callback.

A custom `validate` command fails by exiting nonzero. A Ruby callback fails by raising or returning `false`. A failure skips all later steps and runs `failure` if Ruby is set up.

### Release Version

Set `version: '1.2.3'` to release that version instead of the checked-in one; empty keeps the checked-in version. The standard workflow writes it with the version object's `set!` before updating the changelog. The release commit includes both changes, and the next development version is bumped from it. Callbacks still see the original gemspec version and the captured date.

To pick the version at dispatch time, add a string `version` input to `workflow_dispatch` and pass `version: ${{ inputs.version }}`. Then use the GitHub form or `gh workflow run release.yml -f version=1.2.3`.

Custom `prepare` commands and callbacks must apply the selected version; a mismatched prepared gemspec fails before publication. Custom version objects implement `read`, `set!`, and `increment!`. See [UPGRADING.md](../../UPGRADING.md) for migrations.

### Release Gemfile

To keep `ruby-gem-release` out of your normal bundle, put it in a separate Gemfile that loads the main one, and pass it as `gemfile:`:

```ruby
# gemfiles/release.gemfile
eval_gemfile '../Gemfile'

gem 'commonmarker', '~> 2.10', require: false
gem 'ruby-gem-release', '0.9.0', require: false
```

The workflow sets `BUNDLE_GEMFILE` for the whole job, so every step and default command, including the full `test` suite, uses this bundle. Commit or ignore the lockfile Bundler writes next to it; an untracked lockfile fails the clean-checkout check. In your Rakefile, install the release tasks only when the gem is in the active bundle, so the main bundle works without it:

```ruby
if Gem.loaded_specs.key?('ruby-gem-release')
  require 'ruby-gem-release/workflow/ruby_gem'
  require 'ruby-gem-release/changelog'

  RubyGemRelease::Workflow::RubyGem.new(
    version: RubyGemRelease::Version::RubyConstant.new(path: 'lib/example/version.rb', constant: 'VERSION'),
    changelog: RubyGemRelease::Changelog::KeepAChangelog.new
  ).install_tasks
end
```

Prefer this to `rescue LoadError`, which also hides a real load failure in the gem or its dependencies and silently drops the release tasks.

### Timezone

Set `timezone: America/New_York` to use Eastern Time, including daylight saving. The default is UTC.

The workflow sets `TZ` and records the date once as `RELEASE_DATE`, so it doesn't change if the release runs past midnight. Git commit times are shown in this timezone. GitHub and RubyGems timestamps are not affected.

Use a name from `/usr/share/zoneinfo`, not a fixed offset. Unknown names, empty values, fixed offsets, and paths fail before anything is prepared.

### Success and Failure Callbacks

`success` runs after publication and the version bump succeed. `failure` runs after a failed step, once Ruby is set up. Its callback gets a `RubyGemRelease::ReleaseFailure` with the failed phase, the Ruby exception if there is one (failures reported only by GitHub Actions have none), and the execution context, whose release may be missing. Both do nothing unless you register callbacks. `failure` can't run if the job fails before Ruby setup or is blocked by environment protection.

## Permissions and Authentication

The caller needs `contents: write` to push and create the GitHub Release, and `id-token: write` for Trusted Publishing. Set up the `release` environment and trusted publisher as in [Usage](../../README.md#3-enable-trusted-publishing). You don't store a RubyGems API key.

After setup, anyone with write access can [dispatch the workflow](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow), even in personal repositories, without admin access, RubyGems ownership, or an API key. Dispatching is not approval: with [required reviewers](../../RELEASING.md#maintainer-approved-publication), publication waits for a maintainer to approve the `release` environment. Environments can't limit who dispatches, and one without protection rules restricts nothing.

`release:publish` logs in to the registry just before publishing; there is no separate login step in YAML. For RubyGems, [`RubyGemsCredentials`](../workflow/ruby_gems_credentials.md) exchanges a GitHub OIDC token (audience `rubygems.org`) for a short-lived API key and masks both. It sends `rubygems-owner` for a new gem; leave it empty for an existing gem.

The key is exported as `RUBYGEMS_API_KEY`, `BUNDLE_GEM__PUSH_KEY`, and `GEM_HOST_API_KEY`; `~/.gem/credentials` is not touched. Custom publication commands must use these variables. See the [custom publication contract](../workflow/ruby_gems_credentials.md#custom-publication-commands).

The base destination uses existing credentials, and custom destinations can override login without YAML changes. A `publish` override that skips `release:publish` must log in itself. See [Registry Destinations](../destination.md).

The workflow sets `GH_TOKEN` during publication. Branch rules must allow fast-forward pushes; force-push and deletion restrictions can stay.

## Execution

The job runs on `ubuntu-latest` in the `release` environment with a full checkout. Releases share one concurrency group per repository, so a new release waits rather than canceling a running one.

1. **Capture:** after Ruby setup, the checkout must be clean. Changed, staged, or untracked files fail with their paths. Ruby setup installs gems into `vendor/bundle`, writes `.bundle/config`, and creates a lockfile when none is committed; [ignore them](../../README.md#1-configure-your-gem). When they are not ignored, the error lists the `.gitignore` lines to add. Tracked dependency files are not allowed.
2. **Validate, prepare, test:** files changed by `prepare` are staged before tests. Publication rejects any later change instead of committing it. Custom bump callbacks wrap edits in `git.stage_changes!`, as in [Detailed Usage](../usage.md#custom-callbacks).
3. **Checkpoint:** the workflow commits, builds, and tags locally, then uploads [recovery artifacts](#recovery-artifacts). This must succeed before `publish` and `bump`.
4. **Publish, bump, notify:** any failure stops later steps.

A new release must start from the latest default-branch commit. Each run uses only the current checkout and inputs; it never restores an earlier run, so commands must be safe to rerun. A rerun reuses a matching release commit and tag without rewinding later remote commits. Conflicting tags and unrelated branch changes fail.

## Command Environment

Commands run with `bash -euo pipefail`. An override replaces the whole step and must do its work; registered callbacks don't run unless your command calls them. To turn off only GitHub Releases, set `hosting: nil` (or drop `github.publish!` from custom callbacks) rather than overriding `publish`.

| Variable                          | Availability     | Meaning                                                                              |
| ---                               | ---              | ---                                                                                  |
| `INPUT_VERSION`                   | All phases       | Optional selected release version.                                                   |
| `INPUT_GEMSPEC_PATH`              | All phases       | Optional gemspec path supplied by the caller.                                        |
| `GEMSPEC_PATH`                    | After capture    | Selected absolute gemspec path.                                                      |
| `GEMSPEC_VERSION`                 | After capture    | Gemspec version captured before preparation, retained across callbacks.              |
| `SOURCE_REF`                      | Provider-neutral | Source Git ref; GitHub uses `GITHUB_REF` instead.                                    |
| `SOURCE_COMMIT`                   | After capture    | Source commit hash captured before release preparation.                              |
| `RELEASE_VERSION`                 | After resolution | Prepared version to publish.                                                         |
| `RELEASE_DATE`                    | After capture    | Date captured once in the configured timezone, as `YYYY-MM-DD`.                      |
| `RELEASE_DATA_DIR`                | After capture    | Artifacts and private task data; maps to `RUNNER_TEMP` on Actions, not the checkout. |
| `RELEASE_STATE_FILE`              | After capture    | Private invocation-specific JSON file for callback data.                             |
| `RELEASE_COMMAND`                 | Commands         | Configured shell command for the current phase.                                      |
| `RELEASE_STEP_ID`                 | Commands         | Current enclosing Actions step ID.                                                   |
| `RELEASE_STEPS_JSON`              | Commands         | JSON snapshot of previously observed Actions steps.                                  |
| `RELEASE_FAILED_STEP_ID`          | Failure callback | Failed step or task ID, or `unknown`.                                                |
| `RELEASE_AUTH_MODE`               | After resolution | Destination authentication strategy, or empty for existing credentials.              |
| `DEFAULT_BRANCH`                  | All phases       | Repository default branch.                                                           |
| `GIT_USER_NAME`, `GIT_USER_EMAIL` | All phases       | Configured checkout-local commit identity.                                           |
| `RUBYGEMS_OWNER_ID`               | All phases       | Optional numeric RubyGems account ID for owner-bound authentication.                 |
| `TZ`                              | All phases       | Configured timezone; defaults to `UTC`.                                              |
| `SOURCE_DATE_EPOCH`               | After capture    | Source commit timestamp for reproducible packages, unless explicitly supplied.       |
| `GH_TOKEN`                        | Publish          | GitHub Actions token for hosted releases.                                            |

GitHub also sets variables such as `GITHUB_REPOSITORY` and `RUNNER_TEMP`. See [Execution Context](../execution_context.md), [`Tasks`](../tasks.md), and [`Workflow::Environment`](../workflow/environment.md).

## Recovery Artifacts

Before publishing, the workflow must upload `release.gem` (the built gem), `release.json` (its name, version, and digest), and `release.bundle` (the release commit and tag), kept 30 days as `release-gem-VERSION-RUN_ID-RUN_ATTEMPT`. They are for manual inspection; nothing restores them automatically. See [RELEASING.md](../../RELEASING.md#verify-and-recover).

To publish reviewed commits, stable branches, existing signed tags, or package collections, use the [reviewed workflow](../workflow/reviewed_ruby_gem.md). It keeps the publication checks but makes no commits, tags, pushes, or bumps. Its explicit inputs go in `prepare-artifacts` and `artifacts`; the workflow never searches for artifacts.

### Default Branch Advanced During Publication

Do not merge into the default branch while a release runs. If the branch moves before tagging, the release stops before publishing. If it moves after that, the gem is published but the push fails with `Default branch advanced; start a new release`, leaving no tag, release commit, GitHub Release, or next development version.

Rerunning won't fix this: each run makes a new release commit, and tagging needs the branch at the source commit. Recover by hand from the artifacts, replacing `1.2.3`, `example`, `RUN_ID`, and `ATTEMPT`:

**Step 1.** Download the failed run's artifacts and confirm RubyGems published the preserved archive:

```sh
gh run download RUN_ID -n release-gem-1.2.3-RUN_ID-ATTEMPT -D release-artifacts
jq -r .sha256 release-artifacts/release.json
curl -s https://rubygems.org/api/v1/versions/example.json | jq -r '.[] | select(.number == "1.2.3") | .sha'
```

The digests must match. If they differ, or the version is missing, stop and investigate instead.

**Step 2.** Import the release commit and tag from the bundle, and push the tag. It points at the release commit, whose parent is the dispatched source commit:

```sh
git fetch release-artifacts/release.bundle 'refs/tags/v1.2.3:refs/tags/v1.2.3'
git push origin refs/tags/v1.2.3
```

**Step 3.** Merge the release commit into the default branch through a pull request, resolving conflicts with the changes merged during the release. Do not rewrite or move the tag.

```sh
git switch -c release-1.2.3 v1.2.3
git push origin release-1.2.3
gh pr create --head release-1.2.3 --title 'Release 1.2.3'
```

**Step 4.** Create the GitHub Release with the preserved archive under its gem file name, as normal releases attach it. Write the released changelog section to `NOTES.md`, or replace `--notes-file NOTES.md` with `--generate-notes`:

```sh
cp release-artifacts/release.gem example-1.2.3.gem
gh release create v1.2.3 --verify-tag --title v1.2.3 --notes-file NOTES.md example-1.2.3.gem
```

**Step 5.** Start the next development iteration in a pull request that increments the version and adds the Next changelog section, as the bump would have.

Do not dispatch the same version again. RubyGems only accepts the identical archive, and a rebuilt release commit would not match the pushed tag.
