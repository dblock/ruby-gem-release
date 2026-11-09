# `RubyGemRelease::Workflow::Environment`

Supplies release context checks, invoked through [Tasks](../tasks.md). `Environment.new(provider:)` delegates execution-platform reads and exports to an [ExecutionProvider](../execution_provider.md), selected automatically when omitted. Setup, validation, authentication, artifact uploading, and callback invocation remain pipeline responsibilities. For Actions inputs and defaults, see the [workflow reference](../actions/release.md).

## Configure

`configure!` exports the composite action's input environment, including `TZ`, through the provider. On Actions this writes `GITHUB_ENV`. It validates the timezone and rejects line breaks in all values before writing any of them. The reusable workflow supplies the same values through its job environment and does not need this method.

## Capture

`capture!(package:)` checks the ref and timezone, configures local Git identity, rejects a dirty checkout, reads the initial package version, and checks remote advancement. Tasks supply the configured package; direct calls default to the selected Ruby gem. It exports `TZ`, `GEMSPEC`, `RELEASE_DIRECTORY`, `RELEASE_PREVIOUS_VERSION`, `RELEASE_DATE`, and `RELEASE_INITIAL_COMMIT`. `GEMSPEC` is the package's selected path when available, otherwise empty. The date is captured once in `TZ`, defaulting to UTC.

When the provider supplies a directory, capture also creates a unique private state file and exports `RELEASE_STATE`; otherwise it exports an empty path and callbacks use process-local state. Each new Actions invocation clears previous release environment values before capture. See [Execution Context](../execution_context.md#state).

## Resolve

`resolve!(package:, destination:)` reads the prepared package version, validates optional `INPUT_VERSION`, rejects an existing release tag or a version unavailable at the destination, stages the trusted preparation command's changes and saves the index tree before testing, and exports `RELEASE_VERSION` and `RELEASE_AUTHENTICATION` through the provider. Tasks supply the configured objects; direct calls default to the selected Ruby gem and RubyGems destination. The RubyGems lookup checks the prepared version rather than the initial version; only HTTP 404 permits proceeding. Testing and destination-specific authentication run afterward. Later working tree or index changes are rejected by publication rather than staged automatically.

Standard preparation honors optional `version` through `set!`; custom callbacks must honor it themselves. Resolution rejects a prepared version that differs from the explicit or persisted semantic selection. `RELEASE_PREVIOUS_VERSION` always retains the initial package version.

## Environment

Inputs are `INPUT_GEMSPEC`, `INPUT_VERSION`, `GIT_USER_NAME`, `GIT_USER_EMAIL`, `DEFAULT_BRANCH`, and optional `TZ`, read through the provider. The provider supplies the ref and export mechanism. Timezone identifiers must resolve under `/usr/share/zoneinfo`, as on the supported Ubuntu runners. Configuration also exports `RUBYGEMS_OWNER` for authentication. See the [reusable workflow](../../.github/workflows/release.yml) and [composite action](../../action.yml) for defaults.
