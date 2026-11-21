# Lifecycle Hook Example

The [Rakefile](Rakefile) installs the [project workflow](release_workflow.rb). It uses [release hooks](release_notes.rb) to update this README, and built-in changelog options to remove contribution placeholders and restore a six-category template.

## Stable Release

Development documentation.

## Testing

The [spec](spec/release_spec.rb) copies the workflow and this README into a temporary project. `project.configure_workflow` installs the workflow with local adapters, without changing the real Rakefile. The spec runs a release, checks both Git commits, and verifies that the local registry and hosting adapters received the exact gem. Removing a README hook or the Stable Release section makes it fail.

From the `ruby-gem-release` checkout, run `bundle exec rspec examples/lifecycle_hooks/spec/release_spec.rb`. See [Testing Custom Workflows](../../docs/testing.md) to use the helper in your own project.
