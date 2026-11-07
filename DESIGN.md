# Design

`ruby-gem-release` packages two related interfaces: a reusable GitHub Actions workflow invoked with `workflow_call`, and a Ruby gem that supplies lifecycle Rake tasks and objects for reading, setting, and incrementing numeric versions.

The shared workflow will orchestrate an end-to-end release: authorize the release, validate the requested version, invoke project-configurable preparation and next-version commands, run validation, build and preserve the exact gem artifact, publish with RubyGems Trusted Publishing, push the release commit and tag atomically, and create a GitHub Release. Project-specific changelog and version conventions remain in the calling repository.

The Rake tasks update exactly one constant assignment without evaluating the version file. The reusable workflow is the primary GitHub interface; it is not a composite or JavaScript action. Caller-provided shell commands run with the workflow's privileges and must be trusted.

Optional Ruby callbacks receive an immutable release context during release preparation and next-version preparation. The workflow reads the initial and prepared versions from the gemspec and retains its previous version and UTC date across both phases. An optional version input asserts the prepared version rather than setting it. Callbacks own their version objects with no task-level strategy configuration; `with_version` and `with_next_version` return new release contexts without mutating the originals. Version objects own their file updates; optional changelog objects support `Intridea` and Keep a Changelog formats, including standard version comparison reference links. The caller chooses its objects and owns custom formats and unsupported links; callback failures stop the workflow.

Changelog updates use `Commonmarker` to identify top-level headings and exclude code, HTML, and quoted blocks. Updates edit the original source rather than rendering the parsed document again, preserving unrelated Markdown formatting. Reference definitions are not exposed as separate parser nodes, so comparison references use source-level matching outside those excluded blocks, with parser validation that each reference is defined.

The workflow builds once and publishes before atomically pushing its commit and tag. This leaves an unavoidable recovery window if the push fails after publication; see [RELEASING.md](RELEASING.md). The pull-request integration workflow invokes the actual reusable workflow with a consumer fixture and dry-run mode, without publishing or pushing.

## Logo

The logo in `assets/logo.png` is an original AI-generated image of a ruby gemstone launching like a rocket. This is the original generated asset; no editable source was provided. To create a replacement, generate a centered, text-free, red faceted ruby with an upward launch motif and a transparent background. Generation is not deterministic, so a replacement will differ. Preserve the original asset and inspect the full-size image and its 160-pixel README rendering for legibility and clipping when updating it.
