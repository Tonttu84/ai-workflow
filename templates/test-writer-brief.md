# Test-writer brief: <feature name>

<!-- Experiment, started 2026-11-16: the tests are written before the
     implementation, by a fresh agent that never sees the implementation
     plan. Give it the feature file and AGENTS.md, nothing about how the
     feature will be built. -->

You write the tests for a feature before anyone builds it. You know what a user must be able to do and what must be true afterwards, not how it will be built.

## Inputs

- Project rules: `AGENTS.md` and the shared working agreements it points to.
- The feature file: `docs/features/<feature>.md`: each item, its entry point and its expected outcome.
- Branch or worktree: <name>, based on a freshly fetched `main`; for a feature in a project with feature files, the feature's branch, whose first commit is the feature file.
- Background: <the facts you need, each marked `(checked: <source>)` or `(memory)`, and the owner's words with their level and date: Owner (instruction, 2026-11-16): "...". Or none.>

## For each item

1. Write a failing test that starts at the item's entry point: end to end, HTTP, CLI or the public API. Never call internal functions that do not exist yet: the test must not design the internals.
2. Assert the expected outcome itself, from evidence the test reads back: the database row, the file, the request sent, the page shown. "No error was raised" is not an outcome.
3. Run it and confirm it fails for the right reason: the feature is missing. A typo, an import error or a setup failure is the wrong reason; fix the test until the failure says the feature is missing. In a compiled language, a build error that names only the missing public function or type counts as the right reason.
4. Name the test with the item's tag at its current revision, as `templates/feature.md` shows: `F3-2-r1` where a test name can hold `-` (`test('F3-2-r1 downloads last month as CSV', ...)`), `f3_2_r1` where it cannot (`def test_f3_2_r1_downloads_last_month():`). The gate links only tests whose names carry the tag. In a project whose `AGENTS.md` names OpenFastTrace, also put its coverage comment next to the test, `// [itest->feat~f3-2~1]` (`templates/openfasttrace.md`). Then fill the item's Test cell with the file first, from the top of the repository, then the test's name: `e2e/export.spec.ts, F3-2-r1 downloads last month as CSV`. The gate fails an item whose Test cell does not start with a committed file under a locked path that carries the item's tag at its Rev.

If an item is too vague to test from its entry point, or its outcome cannot be checked, do not guess: list it in the report.

## Then

1. Commit all the tests as one commit: `test(<scope>): lock the tests for <feature>`.
2. In the feature file, replace the placeholder with the line `Locked tests: <paths> at <SHA>`: the test files or directories, separated by spaces and given from the top of the repository, then that commit's SHA. Write it exactly so, at the start of a line, with no Markdown around it: the gate fails a line that only looks like it (`**Locked tests:**`, `- Locked tests:`, another case). Every feature file with items needs one while this experiment lasts. Commit the feature file on its own: `docs(features): record the locked tests for <feature>`.

## Rules

- Tests and their fixtures only: no production code, and no stubs or fakes of the feature itself.
- Use the project's test data and test accounts, never real ones. No network in unit tests; every wait has a deadline.
- The commit hook must pass (never `--no-verify`). Do not push: the locked tests keep the branch's tests red until the feature is built.

## Report

- Per item: the test, and the line that shows it fails because the feature is missing.
- The SHA of the `test:` commit.
- Items you could not test from their entry point, or whose outcome you could not check, and why.
- Decisions you made between real alternatives, one per line in the format of `docs/decisions.md`: `<decision> | <reason> | <chosen against> | YYYY-MM-DD · agent · <evidence> · <one-way or two-way>` (`agent under Dn` when it falls within decision Dn), or none.
- Assumptions you could not verify, one per line: `<assumption> | <why it matters>; <why it could not be checked> | — | YYYY-MM-DD · agent · assumed · two-way`, or none.
