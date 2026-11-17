# <Project name>

<One or two sentences: what this project is and who it is for.>

## Shared rules

This project follows the owner's working agreements: https://github.com/Tonttu84/ai-workflow/blob/main/rules/working-agreements.md
(Claude Code loads them in every session through the user-level `CLAUDE.md`; other tools should read that file.)
This file holds only what is specific to this project and wins where it says so.

## Kind

**Solo** | **Showcase**  <!-- keep one -->

- Solo: commit to `main` and push once the local gate is green; fresh-agent review before pushing any non-trivial change. With feature files, a feature's work stays on its branch until the trace, the black-box test, the review, the hardening and the owner's walkthrough; then the coordinator merges and pushes. A change that adds or revises a feature item is feature work, on its own branch; other bug fixes and small changes go straight to `main`. Tier 1.
- Showcase: branch, pull request, fresh-agent review, squash-merge on the owner's word. Tier 1, plus the tier 2 bonus. With feature files, a required CI check (`<workflow file>`) runs the feature checks and the walkthrough check on each pull request, set up before the first feature pull request merges (ai-workflow D129). Until it exists, the coordinator runs the two checks by hand before each merge. A private repository writes no job, since its Actions minutes are scarce, so there the coordinator always runs them by hand. <!-- keep the last sentence only in a private repository -->

The tiers of verification:

- Tier 1, alignment, in every project: it keeps the owner, the AI, the code and the documentation aligned, and guards against forgetting, hallucination and a false "done", not against tampering.
- Tier 2, audit evidence, a bonus in showcase projects on top of tier 1. Today it means OpenFastTrace tracing, learned in one showcase project with feature files that the owner chooses (ai-workflow D91, D117), and the review metrics drawn from the planted-bug record, which every project keeps (ai-workflow D80). Tamper-resistant records are not yet defined.

## Stack

- Language and framework: <...>
- Data: <database, ORM, schema location>
- Tests: <unit, end-to-end>
- Hosting: <where it runs, if anywhere>

See `docs/kickoff.md` for why this stack was chosen.

## Commands

| Task | Command |
| --- | --- |
| Set up a fresh clone (installs the commit hook) | `<...>` |
| Run the app | `<...>` |
| Unit tests | `<...>` |
| End-to-end tests | `<...>` |
| Lint, format, type-check | `<...>` |
| The local gate (tests, lint, types, build; with feature files, the feature checks below) | `<...>` |

The gate guards `main`: run it before a push to `main` or the merge of a pull request (on the pull request's branch). A push to another branch needs only the `pre-push` commit check, so a feature branch may be pushed while its locked tests are red (ai-workflow D128).

With feature files, the gate also runs `.ai-workflow/check-features.sh --base origin/main` (the branch the work merges into; copied into the project by the ai-workflow `hooks/install.sh --gate`; commit `.ai-workflow/`). For every `Locked tests:` line of every feature file it runs `check-locked-tests.sh` (locked tests unchanged) and `check-red-green.sh` (they fail on the code before the feature and pass on the new code), and checks that each item's Test cell starts with a committed, locked test file that carries the item's tag; then the whole test run, `check-test-count.sh` (the runner finished and no test was lost) and `check-trace-links.sh` (every item has a passing test). A project on OpenFastTrace adds its trace to the gate as a command of its own. Its settings are in the committed `feature-checks.conf` (see `check-features.sh --help`):

```text
test_command = <the test command for one test file, with {path}>
setup = <the install command for a fresh checkout, or none>
run = <the whole test run, which writes the JUnit reports>
count_file = <the count file, such as .test-count; its reports are untracked paths in the repository>
```

## Domain rules

<Rules of the problem the code must keep: invariants, units, money and rounding, time zones, permissions. One line each.>

## Features

**Used** | **Not used**  <!-- keep one; a project without user-visible features (a library, data work) may not use them -->

- Feature files: `docs/features/<feature>.md`, one per feature, from the ai-workflow `templates/feature.md`.
- An entry point here means: <a screen and control | a command | a route | a public function>.
- Expected outcomes are checked in: <the database, output files, a request log, a mail catcher>.
- Traceability: **light** (`.ai-workflow/check-trace-links.sh`) | **light and OpenFastTrace** (the ai-workflow `templates/openfasttrace.md`)  <!-- keep one. Light, unless this is the one showcase project the owner chose for learning OpenFastTrace (ai-workflow D91, D117) -->
- Agent UI runs: **before each release** (no users yet) | **scheduled** (has users) | **none** (finished or abandoned)  <!-- keep one -->
- Third-party services in tests: mocked, unless named here: <a provider's test mode built for automated runs, or none>.

## Layout

<Where things live: entry points, domain logic, IO adapters, tests, fixtures.>

Records under `docs/`: `decisions.md` (the decision log), `escapes.md` (what got past the workflow, and the fix), `research/` (research reports), `features/` (feature files, if used).

## Quirks

<Anything that surprises a newcomer: generated files not to edit, slow tests, flaky external services, environment variables.>

## Decisions

`docs/decisions.md` (D1 onward).
