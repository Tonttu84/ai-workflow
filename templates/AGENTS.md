# <Project name>

<One or two sentences: what this project is and who it is for.>

## Shared rules

This project follows the owner's working agreements: https://github.com/Tonttu84/ai-workflow/blob/main/rules/working-agreements.md
(Claude Code loads them in every session through the user-level `CLAUDE.md`; other tools should read that file.)
This file holds only what is specific to this project and wins where it says so.

## Kind

**Solo** | **Showcase**  <!-- keep one -->

- Solo: commit to `main` and push once the local gate is green; fresh-agent review before pushing any non-trivial change.
- Showcase: branch, pull request, fresh-agent review, squash-merge on the owner's word.

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

With feature files, the gate also runs, from the ai-workflow clone's `scripts/`: `check-locked-tests.sh` (locked tests unchanged), `check-red-green.sh` (they fail on the code before the feature and pass on the new code), `check-test-count.sh` (the runner finished and no test was lost) and `check-trace-links.sh` (or the OpenFastTrace trace).

## Domain rules

<Rules of the problem the code must keep: invariants, units, money and rounding, time zones, permissions. One line each.>

## Features

**Used** | **Not used**  <!-- keep one; a project without user-visible features (a library, data work) may not use them -->

- Feature files: `docs/features/<feature>.md`, one per feature, from the ai-workflow `templates/feature.md`.
- An entry point here means: <a screen and control | a command | a route | a public function>.
- Expected outcomes are checked in: <the database, output files, a request log, a mail catcher>.
- Traceability: **light** (`scripts/check-trace-links.sh`) | **OpenFastTrace** (`templates/openfasttrace.md`)  <!-- keep one; both in the ai-workflow clone -->
- Agent UI runs: **before each release** (no users yet) | **scheduled** (has users) | **none** (finished or abandoned)  <!-- keep one -->
- Third-party services in tests: mocked, unless named here: <a provider's test mode built for automated runs, or none>.

## Layout

<Where things live: entry points, domain logic, IO adapters, tests, fixtures.>

Records under `docs/`: `decisions.md` (the decision log), `escapes.md` (what got past the workflow, and the fix), `research/` (research reports), `features/` (feature files, if used).

## Quirks

<Anything that surprises a newcomer: generated files not to edit, slow tests, flaky external services, environment variables.>

## Decisions

`docs/decisions.md` (D1 onward).
