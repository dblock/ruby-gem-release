# Design

`Package::RubyGem`, `SourceControl::Git`, and `Hosting::GitHubRelease` own release operations through argument-based command invocation. The publication callback commits, builds once, tags, publishes to RubyGems, pushes the commit and tag atomically, and creates the GitHub Release with generated notes and the verified exact artifact. The workflow retains setup, context checks, validation, Trusted Publishing authentication, artifact uploading, and phase invocation. All callbacks run for dry runs; the immutable release context suppresses remote writes in the supplied classes.

`ruby-gem-release` packages two related interfaces: a reusable GitHub Actions workflow invoked with `workflow_call`, and a Ruby gem that supplies lifecycle Rake tasks and objects for reading, setting, and incrementing numeric versions.

The shared workflow will orchestrate an end-to-end release: authorize the release, validate the requested version, invoke project-configurable preparation and next-version commands, run validation, build and preserve the exact gem artifact, publish with RubyGems Trusted Publishing, push the release commit and tag atomically, and create a GitHub Release. Project-specific changelog and version conventions remain in the calling repository.

The Rake tasks update exactly one constant assignment without evaluating the version file. The reusable workflow is the primary GitHub interface; it is not a composite or JavaScript action. Caller-provided shell commands run with the workflow's privileges and must be trusted.

Optional Ruby callbacks receive an immutable release context during release preparation and next-version preparation. The workflow reads the initial and prepared versions from the gemspec and retains its previous version and UTC date across both phases. An optional version input asserts the prepared version rather than setting it. Callbacks own their version objects with no task-level strategy configuration; `with_version` and `with_next_version` return new release contexts without mutating the originals. Version objects own their file updates; optional changelog objects support `Intridea` and Keep a Changelog formats, including standard version comparison reference links. The caller chooses its objects and owns custom formats and unsupported links; callback failures stop the workflow.

Changelog updates use `Commonmarker` to identify top-level headings and exclude code, HTML, and quoted blocks. Updates edit the original source rather than rendering the parsed document again, preserving unrelated Markdown formatting. Reference definitions are not exposed as separate parser nodes, so comparison references use source-level matching outside those excluded blocks, with parser validation that each reference is defined.

The package builds once and publishes before atomically pushing its commit and tag. Git checks concurrency before publication and again before pushing. This leaves an unavoidable recovery window if the push fails after publication; see [RELEASING.md](RELEASING.md). The artifact-upload step runs even when publication fails, preserving the gem, digest manifest, and recovery bundle where available. Because building and publication now share a callback, Actions uploads recovery artifacts afterward rather than beforehand; runner loss during that callback can still lose the local files. The pull-request integration workflow invokes the actual reusable workflow with a consumer fixture and dry-run mode, without publishing or pushing.

## Class Areas

Namespaces group implementations by responsibility: `Package::RubyGem` builds and publishes gems, `SourceControl::Git` manages commits and tags independently of hosting, and `Hosting::GitHubRelease` creates hosted releases. `Version` and `Changelog` retain their existing areas; `Release` and `Tasks` remain shared context and callback registration. `Workflow::Context` captures the Actions release context, while `Workflow::RubyGem` installs the standard sequence. Class, documentation, and spec paths mirror namespaces.

Future hosting implementations can implement `publish!(release, package:)` without changing callbacks or Git operations. No shared hosting base or additional provider is implemented until real shared behavior requires one.

## Standard Workflow

`Workflow::RubyGem` installs the existing callback sequence using explicit version and changelog objects. Package, Git, and hosting objects use their established defaults and can be replaced without changing ordering. Only unambiguous gemspec, repository, branch, and artifact-directory defaults are used; version files and changelog formats are never guessed. An explicit `nil` disables changelog or hosted-release work, not package publication or version incrementing. Custom sequences continue to use `Tasks.install`; no workflow framework or speculative provider abstraction is introduced.

## Project Release Caller

The project's `publish.yml` caller invokes the local reusable workflow through manual dispatch only, using the standard workflow configured in the root Rakefile and the Ruby 4.0 runtime already used by package CI. Dry runs are the caller's default; publishing requires an explicit `dry-run=false` selection and prior release authorization. The caller grants only contents-write and OIDC-token permissions needed for release operations. Trusted Publishing setup remains a separate prerequisite.

## Logo

The logo in `assets/logo.png` is an original AI-generated image of a ruby gemstone launching like a rocket. This is the original generated asset; no editable source was provided. To create a replacement, generate a centered, text-free, red faceted ruby with an upward launch motif and a transparent background. Generation is not deterministic, so a replacement will differ. Preserve the original asset and inspect the full-size image and its 160-pixel README rendering for legibility and clipping when updating it.
