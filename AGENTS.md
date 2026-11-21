# Working on `ruby-gem-release`

Read [CONTRIBUTING.md](CONTRIBUTING.md) for setup, commands, tests, and PR rules, and [DESIGN.md](DESIGN.md) for the design. This project provides GitHub Actions interfaces and Ruby release tasks, not a general-purpose release service.

## Rules to Keep

Do not break these:

- The reusable workflow lives in `.github/workflows/`, the gem API and Rake tasks in `lib/` and `tasks/`, and specs in `spec/`. The root `action.yml` exposes the same tasks as a composite action.
- Support Ruby 3.3 and newer. Use only public RubyGems, Rake, GitHub Actions, and Trusted Publishing interfaces.
- Keep orchestration reusable; calling repositories configure their own preparation and version bump commands.
- Every release action and callback follows the [rerun rules](RELEASING.md#verify-and-recover). Do not add recovery flags, artifact discovery, state restoration, or a completion journal.
- Keep semantic releases opt-in. Versions come from reachable release tags, not development versions. Record one immutable decision, keep it when recording the next version, and never reanalyze during preparation or publication.
- Keep the manual workflow defaults and publication guards unchanged.
- Keep the reusable workflow and composite action consistent. Pin every external action and reusable workflow to a full commit SHA with a trailing version comment, never a tag or branch.
- Keep authentication selection and artifact upload on failure working.
- Do not stub environment exports or installed-gem loading in the portable consumer specs.
- Profile the test harness before and after changing it; do not assume a speedup.
- Keep the logo, its provenance, and its README placement as described in [DESIGN.md](DESIGN.md#self-release-and-artwork).

## Safety

- Never dispatch a publishing workflow from PR CI.
- Do not merge, publish, or create release tags without authorization.
- Never force-push `master`.
- Preserve unrelated worktree changes, and never discard changes to clean up.
