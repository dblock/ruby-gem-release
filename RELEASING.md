# Releasing

Releases will use the shared GitHub Actions workflow and RubyGems Trusted Publishing. Configure a RubyGems trusted publisher for the repository, workflow, and release environment before dispatching a release; do not store long-lived RubyGems API keys in GitHub secrets.

The release process must validate the release version, run the project's checks, prepare release metadata, build the gem once, and publish that exact artifact. It must create the release commit and tag atomically, attach the gem to the GitHub Release, and run the configured next-version task only after publication succeeds.

Verify the version on RubyGems, the matching Git tag, GitHub Release, and next development version after release. Published gem versions and release tags must never be overwritten or moved. This document describes the intended process and does not authorize publishing.
