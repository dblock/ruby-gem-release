# `RubyGemRelease::Workflow::Environment`

Supplies release context checks, invoked through [Tasks](../tasks.md). `Environment.new(provider:)` delegates execution-platform reads and exports to an [ExecutionProvider](../execution_provider.md), selected automatically when omitted. Setup, validation, authentication, artifact uploading, and callback invocation remain pipeline responsibilities. For Actions inputs and defaults, see the [workflow reference](../actions/release.md).

## Configure

`configure!` exports the composite action's input environment, including `TZ`, through the provider. On Actions this writes `GITHUB_ENV`. It validates the timezone and rejects line breaks in all values before writing any of them. The reusable workflow supplies the same values through its job environment and does not need this method.

## Capture

`capture!(package:)` checks the ref and timezone, configures local Git identity, rejects a dirty checkout, reads the initial package version, and checks remote advancement. Tasks supply the configured package; direct calls default to the selected Ruby gem. It exports `TZ`, `GEMSPEC_PATH`, `RELEASE_DATA_DIR`, `GEMSPEC_VERSION`, `RELEASE_DATE`, `SOURCE_COMMIT`, and `SOURCE_DATE_EPOCH`. `GEMSPEC_PATH` is the package's selected path when available, otherwise empty. The release date is captured once in `TZ`, defaulting to UTC.

`SOURCE_COMMIT` is the checkout commit hash captured before release preparation, not necessarily the later commit tagged for publication. `SOURCE_DATE_EPOCH` is its committer timestamp in Unix seconds, unless an explicit value was supplied. It controls package timestamps independently of generated release commits and the release calendar date.

When the provider supplies a directory, capture also creates a unique private state file and exports `RELEASE_STATE_FILE`; otherwise it exports an empty path and callbacks use process-local state. See [Execution Context](../execution_context.md#state).

## Resolve

`resolve!(package:, destination:)` reads the prepared version, validates optional `INPUT_VERSION`, stages trusted preparation outputs, and saves the index tree before testing. It exports `RELEASE_VERSION` and `RELEASE_AUTH_MODE` through the provider. Tasks supply configured objects; direct calls default to the selected Ruby gem and RubyGems destination. Publishing tasks enforce checksum and Git-ref postconditions; resolution does not reject an existing publication. Later working tree or index changes are rejected rather than staged automatically.

Standard preparation honors optional `version` through `set!`; custom callbacks must honor it themselves. Resolution rejects a prepared version that differs from the explicit or persisted semantic selection. `GEMSPEC_VERSION` always retains the initial package version.

## Environment

Inputs are `INPUT_GEMSPEC_PATH`, `INPUT_VERSION`, `GIT_USER_NAME`, `GIT_USER_EMAIL`, `DEFAULT_BRANCH`, and optional `TZ`, read through the provider. The provider supplies the ref and export mechanism. Timezone identifiers must resolve under `/usr/share/zoneinfo`, as on the supported Ubuntu runners. Configuration also exports `RUBYGEMS_OWNER_ID` for authentication. See the [reusable workflow](../../.github/workflows/release.yml) and [composite action](../../action.yml) for defaults.
