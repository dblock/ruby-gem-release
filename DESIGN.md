# Design

`ruby-gem-release` will package two related interfaces: a reusable GitHub Actions workflow invoked with `workflow_call`, and a Ruby gem that supplies Rake tasks for common Ruby gem release operations such as version increments.

The shared workflow will orchestrate an end-to-end release: authorize the release, validate the requested version, invoke project-configurable preparation and next-version commands, run validation, build and preserve the exact gem artifact, publish with RubyGems Trusted Publishing, push the release commit and tag atomically, and create a GitHub Release. Project-specific changelog and version conventions remain in the calling repository.

The gem's Rake tasks will provide convenient defaults for common release chores without preventing a project from supplying its own commands. The reusable workflow is the primary GitHub interface; it is not a composite or JavaScript action.

The initial scaffold does not implement release behavior. Follow-up implementation work will define the task configuration and workflow inputs, and will validate the reusable workflow against an actual consumer fixture.
