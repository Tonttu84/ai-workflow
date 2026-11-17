# Agent brief: <task title>

<!-- For a coding subagent. This brief is all the context it gets: no
     conversation history, no "as discussed". Fill every section. -->

## Goal

<What should be true when you are done, in one paragraph. Link the task id if there is one.>

## Context

- Project rules: `AGENTS.md`, plus the shared working agreements it points to.
- Read first: <files, docs, decisions (D-numbers) that matter>.
- Background: <the facts the coordinator learned that you need, each marked `(checked: <source>)` or `(memory)`. Quote the owner's words with their level and date: Owner (instruction, 2026-11-16): "...". Text without a level is the coordinator's choice (`agent`); the owner's words always carry one.>
- Levels: `instruction`: follow it; ask before changing it. `preference`: the default; deviate only with the reason in your report. `idea`: open to challenge. `agent`: the coordinator's choice; a better one can replace it as a decision you report.

## Tried, didn't work

<!-- Optional, for a re-brief; delete otherwise. -->

- <attempt>: <what it did>; failed because <why>. Kept on branch <name>.

## Locked tests

<!-- Optional, when a test writer ran; delete otherwise. The gate's
     .ai-workflow/check-features.sh checks them before a push to main or
     the merge of a pull request. -->

- <paths> at <SHA>. Make them pass; never edit them. If one looks wrong, stop and report why.

## Scope

- Change: <files or areas you may touch>.
- Leave alone: <files or areas you must not touch>.
- Out of scope: <related things not to do now; mention them in the report instead>.

## Tests first

- <The failing test(s) to write before the code, and where they go.>
- Never weaken, skip or delete an existing test. If one looks wrong, stop and report why; the coordinator then fixes it as its own change.

## Work rules

- Branch or worktree: <name>, based on a freshly fetched `main`; with locked tests, on the feature's branch at <the test writer's SHA>, where they are.
- Commits: Conventional Commits, one logical change each; the commit hook must pass (never `--no-verify`). Task id in a `Refs:` footer.
- Push / PR: <solo: push to main when the local gate is green | solo, feature work in a project with feature files: commit on the feature's branch and push only that branch. Push it at any time, for backup and review fixes. A branch push needs only the commit check, so it may go up while the locked tests are red. Verify must still pass before you report it done. The coordinator runs the gate and merges the branch after the walkthrough | showcase: open a PR, do not merge>.
- Ask instead of guessing on: <anything that is the owner's decision>.
- Two strikes: if you fail twice to fix the same problem (a failing test, a review finding, a gate error), stop. Commit the attempt on your branch and report what you tried and why each attempt failed. Do not try a third time.
- Scratch files (reports, CSVs, logs) outside the worktree get a name that starts with the project and task, such as `<project>-<task>-lizard.csv`: parallel agents share scratch folders and overwrite each other's `lizard.csv`.

## Verify

Run these and paste the result lines in the report:

```text
<the gate command, e.g. npm run check && npm test>
```

## Report

- What you changed, with commit SHAs.
- Test results: the commands you ran and their pass/fail counts.
- What you did not do or could not verify, and why.
- Decisions you made between real alternatives, one per line in the format of `docs/decisions.md`: `<decision> | <reason> | <chosen against> | YYYY-MM-DD · agent · <evidence> · <one-way or two-way>` (`agent under Dn` when it falls within decision Dn).
- Assumptions you could not verify, one per line: `<assumption> | <why it matters>; <why it could not be checked> | — | YYYY-MM-DD · agent · assumed · two-way`, or none.
- Deviations from an owner `preference`, each with its reason.
- Anything surprising you found outside the scope.
