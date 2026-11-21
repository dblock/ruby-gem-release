# Contributing

Make one focused change per pull request.

- Use a separate worktree for each PR, on a `dblock/<topic>` branch from `master`. Keep the primary checkout on `master` when it is clean.
- Ordinary changes go through PRs. Only authorized release automation pushes directly, for release and next development commits. The default-branch ruleset blocks force pushes and deletion but does not require PRs, so release automation and other writers can push fast-forward commits.
- After a PR merges, confirm it merged and check for uncommitted changes and dependent work. Then remove the clean worktree and local branch. Never discard work to clean up.

## Setup and Validation

Ruby 3.3 or newer is supported.

```sh
bundle install
bundle exec rake
bundle exec rake build
```

`bundle exec rake` runs the specs and RuboCop; run it before every push. `bundle exec rake build` builds the gem when packaging changes. Danger checks the changelog in PR CI; you do not run it locally.

RuboCop also checks documentation and YAML:

- `rubocop-prose` checks Markdown prose.
- `rubocop-md` checks Ruby code blocks in Markdown.
- `rubocop-spellcheck` checks spelling in comments and documentation, not Ruby strings.
- `rubocop-yaml` checks YAML.

Keep each paragraph on one source line. Fix spelling mistakes; add only reviewed project words to `.spellcheck.txt`. The license text is excluded from spelling and paragraph-length checks.

Danger runs through the reusable [danger-pr-comment](https://github.com/danger/danger-pr-comment) workflows. A read-only PR job checks out full history and runs `danger dry_run`, which saves a report instead of commenting. A separate `workflow_run` job posts the report without checking out or running contributed code. It skips empty reports but always updates an existing report comment. Keep full history so fork commits and their merge base are available. The commenting workflow only responds once it is on `master`.

## Tests

Every release action must follow the [rerun rules](RELEASING.md#verify-and-recover). Test success with a lost response, reruns, and checksum or tag conflicts.

Specs live in `spec/`. Add focused specs for task behavior, and use real consumer projects to run the commands of the reusable workflow and composite action. Coverage reports (HTML and LCOV) go to `coverage/`, and CI uploads them to Coveralls.

| Command                             | Runs                                                                   |
| ---                                 | ---                                                                    |
| `bundle exec rake spec:unit`        | Source specs, excluding `spec/integration/`. Run by the Test workflow. |
| `bundle exec rake spec:integration` | Consumer integration specs. CI runs them on the installed gem.         |
| `bundle exec rake spec`             | The full suite, in parallel.                                           |
| `bundle exec rake spec:serial`      | The full suite, serially.                                              |
| `bundle exec rake`                  | The full suite plus RuboCop.                                           |

Unit specs cover documented configurations, timezone and version behavior, and YAML and shell contracts in-process, without creating consumer repositories. CI does not run integration specs against source.

`spec` and `spec:integration` run spec files in parallel with `parallel_tests` and merge coverage at the end. Workers default to the number of processors.

- `PARALLEL_TEST_PROCESSORS=2` limits workers.
- `SPEC=spec/path_spec.rb` selects files.
- `SPEC_OPTS='--seed 12345'` passes RSpec options.

### Integration Specs

Integration specs live in `spec/integration/composite`, `spec/integration/workflow`, and `spec/integration/consumer`. CI runs each directory as a matrix entry per supported Ruby. Put new integration specs in one of these directories; files elsewhere run locally but not in CI. Run one suite with:

```sh
SPEC='spec/integration/consumer/**/*_spec.rb' bundle exec rake spec:integration
```

Keep this real-process matrix small. It covers both Actions interfaces: success, failure and recovery, empty-release rejection, a custom registry, and credential propagation. Keep the provider-neutral consumers running across separate processes; they check environment exports, private state, and loading the installed gem. Semantic consumer fixtures cover success, publication failure, and empty-release rejection against the installed gem. Stub orchestration in focused specs, not in these smoke tests. Domain specs cover format, version, timezone, Git, and authentication edge cases.

The release integration workflow builds and installs the real gem. It runs both interfaces' commands with real pushes to local Git remotes and fake RubyGems and GitHub publication; unexpected network requests fail. Tests check release and next development commits, artifact identity, and publication order, without publishing anything. They do not test live Actions authentication or artifact upload, so preserve authentication selection and upload-on-failure behavior when you change either interface. When you change YAML interfaces, check installed-gem consumer CI and validate the workflows with:

```sh
actionlint .github/workflows/*.yml examples/.github/workflows/*.yml
```

To profile integration specs, run the command below. Compare before and after on the same machine and Ruby, including subprocess counts when you change the harness. Do not enforce timing thresholds.

```sh
bundle exec rake spec:integration SPEC_OPTS='--profile 15 --seed 12345'
```

## Pull Requests

- Keep one coherent commit per PR. Amend it and push with `git push --force-with-lease` on the topic branch.
- Squash and rebase merges are allowed; merge commits are disabled.
- Update affected documentation.
- Add user-visible changes to the Next section of `CHANGELOG.md`, oldest first, with the PR link and author, above `- Your contribution here.`, which stays last.

See [RELEASING.md](RELEASING.md) for releases.
