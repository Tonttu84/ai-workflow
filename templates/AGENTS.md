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
| The gate (everything CI runs) | `<...>` |

## Domain rules

<Rules of the problem the code must keep: invariants, units, money and rounding, time zones, permissions. One line each.>

## Layout

<Where things live: entry points, domain logic, IO adapters, tests, fixtures.>

## Quirks

<Anything that surprises a newcomer: generated files not to edit, slow tests, flaky external services, environment variables.>

## Decisions

`docs/decisions.md` (D1 onward).
