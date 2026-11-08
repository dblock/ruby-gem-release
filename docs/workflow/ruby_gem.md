# `RubyGemRelease::Workflow::RubyGem`

Installs the standard Ruby gem release sequence through [`Tasks`](../tasks.md), using the existing package, source control, and hosting objects. See [Usage](../../README.md#usage) for the minimal setup or [Detailed Usage](../usage.md) for manual callbacks.

## Version

The required `version:` object implements `read` and `increment!`. Preparation reads its current version for the changelog; next development iteration preparation increments it. The default [`RubyConstant`](../version/ruby_constant.md) increment is a patch change. Version files are never guessed.

## Changelog

The required `changelog:` object implements `release!(release)` and `prepare_next!(release)`. Choose [`KeepAChangelog`](../changelog/keep_a_changelog.md) or [`Intridea`](../changelog/intridea.md) explicitly. Set `changelog: nil` to skip changelog updates without skipping version incrementing.

## Package

The optional `package:` defaults to [`Package::RubyGem`](../package/ruby_gem.md). It selects `GEMSPEC` or the only root gemspec and owns artifact construction, verification, and publication. Override it with an object implementing `build!(release)` and `publish!(release)`, plus `artifact(release)` when required by your hosting object.

## Git

The optional `git:` defaults to [`SourceControl::Git`](../source_control/git.md). It implements `commit!`, `tag!`, `push!`, and `commit_next!`. Branch and artifact-directory defaults come from the workflow environment or checkout. Git identity is configured by the Actions context checks; task installation alone does not alter Git configuration.

## Hosting

The optional `hosting:` defaults to [`Hosting::GitHubRelease`](../hosting/github_release.md), using the repository from Actions or the checkout. A custom object implements `publish!(release, package:)`. Set `hosting: nil` to disable hosted releases without disabling package publication or Git pushes.

## Install Tasks

`install_tasks` registers preparation, publication, next development iteration, and workflow-context tasks. It does not immediately release or change project files. Use it instead of manual `Tasks.install` callback configuration, not alongside another installation.

Preparation updates the changelog with the explicitly read version. Publication commits release changes, builds once, tags locally, publishes the package, pushes the release commit and tag atomically, then publishes the hosted release. Next development iteration preparation increments the version, updates the changelog, passes the updated context to `commit_next!`, and pushes only the next development iteration commit.

## Errors

Errors propagate through the tasks and stop the sequence. The default objects preserve concurrency checks, artifact verification, recovery bundles, and package-before-tag publication. Every callback receives an immutable release context; overrides must preserve the publication order and artifact identity.
