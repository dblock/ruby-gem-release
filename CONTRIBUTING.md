# Contributing

Create a topic branch from `master` and keep each pull request focused on one coherent change.

## Setup and Validation

Ruby 3.3 or newer is supported. Install dependencies with `bundle install`, run the specs and RuboCop with `bundle exec rake`, construct the gem with `bundle exec rake build`, and run the changelog check with `bundle exec danger`.

RuboCop includes Markdown prose checks with `rubocop-prose`, Ruby code block checks with `rubocop-md`, and spelling checks with `rubocop-spellcheck`. Keep paragraphs on one source line, fix spelling mistakes, and add reviewed project vocabulary to `.spellcheck.txt`. Repository spelling checks cover comments and documentation, not Ruby strings; the standard license text is excluded from spelling and paragraph-length checks.

## Tests

RSpec examples live in `spec/`; add focused examples for release-task behavior and use a real consumer fixture for reusable-workflow integration. Specs write HTML and LCOV coverage reports under `coverage/`, which CI uploads to Coveralls.

## Pull Requests

Please use one coherent commit for most PRs; multiple commits are welcome when they represent useful, independently reviewable changes. Squash and rebase merges are supported; merge commits are disabled. Update documentation for user-visible changes and add notable behavior changes to the `0.1.0 (Next)` section of `CHANGELOG.md` with the PR link and author attribution once available. Keep Markdown paragraphs on one source line. See [RELEASING.md](RELEASING.md) for release procedures.
