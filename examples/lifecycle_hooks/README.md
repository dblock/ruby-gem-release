# Lifecycle Hook Example

The [Rakefile](Rakefile) installs the [project workflow](release_workflow.rb), which uses [release hooks](release_notes.rb) to update this README and built-in changelog options to clean contribution placeholders and restore its six-category template.

## Stable Release

Development documentation.

## Testing

The [complete spec](spec/release_spec.rb) copies the actual workflow and this README into a disposable project. `project.configure_workflow` installs that builder with local adapters without changing the production Rakefile. The spec runs the release, checks both Git commits, and verifies that the registry and hosting adapters stored the exact archive locally. Deleting a README hook or removing the stable-release paragraph causes the spec to fail.

From the `ruby-gem-release` checkout, run `bundle exec rspec examples/lifecycle_hooks/spec/release_spec.rb`. See [Testing Custom Workflows](../../docs/testing.md) to adapt the helper to your own project.
