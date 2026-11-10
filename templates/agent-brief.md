# Agent brief: <task title>

<!-- For a coding subagent. This brief is all the context it gets: no
     conversation history, no "as discussed". Fill every section. -->

## Goal

<What should be true when you are done, in one paragraph. Link the task id if there is one.>

## Context

- Project rules: `AGENTS.md`, plus the shared working agreements it points to.
- Read first: <files, docs, decisions (D-numbers) that matter>.
- Background: <the facts the coordinator learned that you need; quote the owner's words with the date where they decide something>.

## Scope

- Change: <files or areas you may touch>.
- Leave alone: <files or areas you must not touch>.
- Out of scope: <related things not to do now; mention them in the report instead>.

## Tests first

- <The failing test(s) to write before the code, and where they go.>
- Never weaken, skip or delete an existing test. If one looks wrong, stop and report it.

## Work rules

- Branch or worktree: <name>, based on a freshly fetched `main`.
- Commits: Conventional Commits, one logical change each; the commit hook must pass (never `--no-verify`). Task id in a `Refs:` footer.
- Push / PR: <solo: push to main when the gate is green | showcase: open a PR, do not merge>.
- Ask instead of guessing on: <anything that is the owner's decision>.

## Verify

Run these and paste the result lines in the report:

```text
<the gate command, e.g. npm run check && npm test>
```

## Report

- What you changed, with commit SHAs.
- Test results: the commands you ran and their pass/fail counts.
- What you did not do or could not verify, and why.
- Decisions you made between real alternatives (for `docs/decisions.md`).
- Anything surprising you found outside the scope.
