# Design

`Package::RubyGem`, `SourceControl::Git`, and `Hosting::GitHubRelease` own release operations through argument-based command invocation. The publication callback commits, builds once, tags, publishes to RubyGems, pushes the commit and tag atomically, and creates the GitHub Release with generated notes and the verified exact artifact. The workflow retains setup, context checks, validation, Trusted Publishing authentication, artifact uploading, and phase invocation. Release callbacks receive an immutable version and date context; publication methods perform their remote writes.

`ruby-gem-release` supplies a reusable GitHub Actions workflow invoked with `workflow_call`, a step-based composite action, and a Ruby gem with shared lifecycle Rake tasks and objects for reading, setting, and incrementing numeric versions.

The shared workflow will orchestrate an end-to-end release: authorize the release, validate the requested version, invoke project-configurable preparation and next development iteration commands, run validation, build and preserve the exact gem artifact, publish with RubyGems Trusted Publishing, push the release commit and tag atomically, and create a GitHub Release. Project-specific changelog and version conventions remain in the calling repository.

The Rake tasks update exactly one constant assignment without evaluating the version file. The reusable workflow is the primary GitHub interface; a composite action offers the same release lifecycle as a caller-owned job step. Caller-provided shell commands run with the workflow's privileges and must be trusted.

Optional Ruby callbacks receive an immutable release context during release preparation and next development iteration preparation. The workflow reads the initial and prepared versions from the gemspec and retains its previous version and UTC date across both phases. An optional version input asserts the prepared version rather than setting it. Callbacks own their version objects with no task-level strategy configuration; `with_version` and `with_next_version` return new release contexts without mutating the originals. Version objects own their file updates; optional changelog objects support `Intridea` and Keep a Changelog formats, including standard version comparison reference links. The caller chooses its objects and owns custom formats and unsupported links; callback failures stop the workflow.

Changelog updates use `Commonmarker` to identify top-level headings and exclude code, HTML, and quoted blocks. Updates edit the original source rather than rendering the parsed document again, preserving unrelated Markdown formatting. Reference definitions are not exposed as separate parser nodes, so comparison references use source-level matching outside those excluded blocks, with parser validation that each reference is defined.

The package builds once and publishes before atomically pushing its commit and tag. Git checks concurrency before publication and again before pushing. This leaves an unavoidable recovery window if the push fails after publication; see [RELEASING.md](RELEASING.md). The artifact-upload step runs even when publication fails, preserving the gem, digest manifest, and recovery bundle where available. Because building and publication now share a callback, Actions uploads recovery artifacts afterward rather than beforehand; runner loss during that callback can still lose the local files. Pull-request integration builds and installs the gem and executes both interfaces' callback commands in real consumers. Only package uploads and hosted-release creation are isolated; Git pushes use local bare repositories. These checks do not execute live Actions authentication or artifact uploading.

## Class Areas

Namespaces group implementations by responsibility: `Package::RubyGem` builds and publishes gems, `SourceControl::Git` manages commits and tags independently of hosting, and `Hosting::GitHubRelease` creates hosted releases. `Version` and `Changelog` retain their existing areas; `Release` and `Tasks` remain shared context and callback registration. `Workflow::Context` captures the Actions release context, while `Workflow::RubyGem` installs the standard sequence. Class, documentation, and spec paths mirror namespaces.

Future hosting implementations can implement `publish!(release, package:)` without changing callbacks or Git operations. No shared hosting base or additional provider is implemented until real shared behavior requires one.

## Standard Workflow

`Workflow::RubyGem` installs the existing callback sequence using explicit version and changelog objects. Package, Git, and hosting objects use their established defaults and can be replaced without changing ordering. Only unambiguous gemspec, repository, branch, and artifact-directory defaults are used; version files and changelog formats are never guessed. An explicit `nil` disables changelog or hosted-release work, not package publication or version incrementing. Custom sequences continue to use `Tasks.install`; no workflow framework or speculative provider abstraction is introduced.

## Composite Action

The root `action.yml` is the single Marketplace action metadata file. It invokes the same Ruby lifecycle tasks, authentication paths, and exact-artifact publication as the reusable workflow. Its input configuration uses `Workflow::Context` to validate and export values across composite steps before preparation. Callers own job permissions, runner, environment, and concurrency; the reusable workflow continues to provide those settings without changing existing consumers.

Both YAML interfaces keep thin orchestration wrappers over the Ruby implementation. The reusable workflow deliberately does not reference a moving composite-action branch or a future release tag: a pinned workflow must remain independent of later action versions. Real consumer CI exercises both interfaces and verifies recovery artifacts and skipped iteration preparation after a failed action callback. Both interfaces use the same release versions, and published tags remain immutable.

## Project Release Caller

The project's `publish.yml` caller invokes the local reusable workflow through manual dispatch only, using the standard workflow configured in the root Rakefile and the Ruby 4.0 runtime already used by package CI. Every dispatch publishes and requires prior release authorization. The caller grants only contents-write and OIDC-token permissions needed for release operations. Trusted Publishing setup remains a separate prerequisite.

The root Rakefile uses the project-local `ReleaseVersion` subclass of `Version::RubyConstant`. Its `increment!` updates README action and reusable-workflow references to the version just released while returning the version for the next development iteration. README edits are committed with the next development iteration, not the already-created release tag. The shared workflow and gem API remain unchanged.

### Owner-Bound Authentication

First publication with a pending trusted publisher requires the RubyGems account ID in the OIDC exchange. `Workflow::RubyGemsCredentials` uses Ruby's standard HTTP and JSON libraries because the released credentials action does not yet support this owner assertion. It masks both tokens, exports the short-lived key through `GITHUB_ENV`, and makes no retry or persistent credential-file writes. The optional `rubygems-owner` input selects this helper; an empty input retains the pinned credentials action for existing gems. The project's caller reads the account ID from the non-secret `RUBYGEMS_OWNER_ID` repository variable.

## Logo

The logo in `assets/logo.png` is an original AI-generated image of a ruby gemstone launching like a rocket. This is the original generated asset; no editable source was provided. To create a replacement, generate a centered, text-free, red faceted ruby with an upward launch motif and a transparent background. Generation is not deterministic, so a replacement will differ. Preserve the original asset and inspect the full-size image and its 160-pixel README rendering for legibility and clipping when updating it.
