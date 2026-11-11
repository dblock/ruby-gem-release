# Lifecycle Hook Example

The [Rakefile](Rakefile) installs the [project workflow](release_workflow.rb), which uses [release hooks](release_notes.rb) to update this README and the changelog.

## Stable Release

Development documentation.

## Testing

The [complete spec](spec/release_spec.rb) copies the actual workflow and this README into a disposable project. It replaces registry and hosting publication with local adapters, runs the release, and checks both Git commits. Deleting a README hook or removing the stable-release paragraph causes the spec to fail.

From the `ruby-gem-release` checkout, run `bundle exec rspec examples/lifecycle_hooks/spec/release_spec.rb`. See [Testing Custom Workflows](../../docs/testing.md) to adapt the helper to your own project.
