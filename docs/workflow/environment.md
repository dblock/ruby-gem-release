# `RubyGemRelease::Workflow::Environment`

`Environment` checks the release context and exports values for later steps; [Tasks](../tasks.md) call it for you. It works through an [ExecutionProvider](../execution_provider.md), chosen automatically unless you pass `Environment.new(provider:)`. It does not handle setup, validation, authentication, artifact uploads, or callbacks. For Actions inputs and defaults, see the [workflow reference](../actions/release.md).

## Configure

`configure!` exports the composite action's inputs, including `TZ`, to `GITHUB_ENV` on Actions. It checks the timezone and rejects line breaks in all values before writing any. The reusable workflow sets these values in its job environment instead.

## Capture

`capture!(package:)` records the starting point of a release. It checks the ref and timezone, sets the local Git identity, fails on a dirty checkout, reads the current package version, and fails if the remote branch has diverged from your checkout. Tasks pass the configured package; direct calls default to the selected Ruby gem.

It exports:

- `TZ`: the timezone, `UTC` by default.
- `GEMSPEC_PATH`: the package's gemspec path, or empty.
- `RELEASE_DATA_DIR`: the provider's directory for release data.
- `GEMSPEC_VERSION`: the version before release. It never changes.
- `RELEASE_DATE`: today's date in `TZ`, computed once.
- `SOURCE_COMMIT`: the checkout commit before preparation, not the commit that is later tagged.
- `SOURCE_DATE_EPOCH`: the committer time of `SOURCE_COMMIT` in Unix seconds, unless you set it. It sets package timestamps.
- `RELEASE_STATE_FILE`: a new private state file when the provider has a directory; otherwise empty, and state stays in memory. See [Execution Context](../execution_context.md#state).

## Resolve

`resolve!(package:, destination:)` runs after preparation and before tests. It reads the prepared version and fails if it differs from `INPUT_VERSION` or the saved semantic decision. It then stages the prepared files, saves a snapshot of the Git index, and exports `RELEASE_VERSION` and `RELEASE_AUTH_MODE`. Direct calls default to the selected Ruby gem and RubyGems.

Later changes to the working tree or index are rejected, never staged. An existing publication does not fail resolution; publishing tasks check checksums and Git refs. Standard preparation applies an explicit `version` with `set!`; custom callbacks must apply it themselves.

## Environment

The provider supplies the ref, the export mechanism, and these inputs: `INPUT_GEMSPEC_PATH`, `INPUT_VERSION`, `GIT_USER_NAME`, `GIT_USER_EMAIL`, `DEFAULT_BRANCH`, and optional `TZ`. The timezone must exist under `/usr/share/zoneinfo`, as on the supported Ubuntu runners. `configure!` also exports `RUBYGEMS_OWNER_ID` for authentication. See the [reusable workflow](../../.github/workflows/release.yml) and [composite action](../../action.yml) for defaults.
