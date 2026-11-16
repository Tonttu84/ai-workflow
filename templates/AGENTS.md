# <Project name>

<One or two sentences: what this project is and who it is for.>

## Shared rules

This project follows the owner's working agreements: https://github.com/Tonttu84/ai-workflow/blob/main/rules/working-agreements.md
(Claude Code loads them in every session through the user-level `CLAUDE.md`; other tools should read that file.)
This file holds only what is specific to this project and wins where it says so.

## Kind

**Solo** | **Showcase**  <!-- keep one -->

- Solo: commit to `main` and push once the local gate is green; fresh-agent review before pushing any non-trivial change. With feature files, a feature's work stays on its branch until the trace, the black-box test, the review and the owner's walkthrough; then the coordinator merges and pushes. Bug fixes and small changes go straight to `main`. Tier 1.
- Showcase: branch, pull request, fresh-agent review, squash-merge on the owner's word. Tier 1, plus the tier 2 bonus.

The tiers of verification:

- Tier 1, alignment, in every project: it keeps the owner, the AI, the code and the documentation aligned, and guards against forgetting, hallucination and a false "done", not against tampering.
- Tier 2, audit evidence, a bonus in showcase projects on top of tier 1. Today it means OpenFastTrace tracing where the project uses feature files (the owner chose to learn it now in a showcase project: ai-workflow D91) and the review metrics (the planted-bug record). Tamper-resistant records are not yet defined.

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
| The local gate before every push (tests, lint, types, build; with feature files, the feature checks below) | `<...>` |

With feature files, the gate also runs `.ai-workflow/check-features.sh --base <the branch the push goes to, such as origin/main>` (copied into the project by the ai-workflow `hooks/install.sh --gate`; commit `.ai-workflow/`). For every `Locked tests:` line of every feature file it runs `check-locked-tests.sh` (locked tests unchanged) and `check-red-green.sh` (they fail on the code before the feature and pass on the new code); then the whole test run, `check-test-count.sh` (the runner finished and no test was lost) and `check-trace-links.sh` (every item has a passing test). A project on OpenFastTrace adds its trace to the gate as a command of its own. Its settings are in the committed `feature-checks.conf` (see `check-features.sh --help`):

```text
test_command = <the test command for one test file, with {path}>
setup = <the install command for a fresh checkout, or none>
run = <the whole test run, which writes the JUnit reports>
count_file = <the count file, such as .test-count>
```

## Domain rules

<Rules of the problem the code must keep: invariants, units, money and rounding, time zones, permissions. One line each.>

## Features

**Used** | **Not used**  <!-- keep one; a project without user-visible features (a library, data work) may not use them -->

- Feature files: `docs/features/<feature>.md`, one per feature, from the ai-workflow `templates/feature.md`.
- An entry point here means: <a screen and control | a command | a route | a public function>.
- Expected outcomes are checked in: <the database, output files, a request log, a mail catcher>.
- Traceability: **light** (`scripts/check-trace-links.sh`) | **light and OpenFastTrace** (`templates/openfasttrace.md`)  <!-- keep one; both in the ai-workflow clone. Light in a solo project; light and OpenFastTrace in a showcase project (ai-workflow D91) -->
- Agent UI runs: **before each release** (no users yet) | **scheduled** (has users) | **none** (finished or abandoned)  <!-- keep one -->
- Third-party services in tests: mocked, unless named here: <a provider's test mode built for automated runs, or none>.

## Layout

<Where things live: entry points, domain logic, IO adapters, tests, fixtures.>

Records under `docs/`: `decisions.md` (the decision log), `escapes.md` (what got past the workflow, and the fix), `research/` (research reports), `features/` (feature files, if used).

## Quirks

<Anything that surprises a newcomer: generated files not to edit, slow tests, flaky external services, environment variables.>

## Decisions

`docs/decisions.md` (D1 onward).
