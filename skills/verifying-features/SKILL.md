---
name: verifying-features
description: The coordinator's pipeline for a user-visible feature in a project whose AGENTS.md uses feature files, from the feature items written before any code, through locked tests, the trace, the black-box test and the review, to hardening with mutation testing, the push gate and the owner's walkthrough. Use it whenever you, as the coordinator, plan, build, review, harden or ship a feature, set up the feature checks in a project, or decide on agent-driven UI runs. Err toward using it too often rather than too rarely. Subagents follow the brief they are given instead.
---

# Verifying features

For the coordinator. Each step's agent gets its template, which carries the rules it needs; the paths here are in the ai-workflow clone. Whether a project uses feature files, and its entry points, outcome evidence, traceability and UI runs, are in its `AGENTS.md`.

A feature's work stays on its own branch from the test writer to the walkthrough, in a solo project too (the owner's instruction, D98). The branch may be pushed for backup at any time; it reaches `main` only after the trace, the black-box test, the review and the walkthrough, and then you merge and push. Bug fixes and small changes keep the normal solo flow.

## The principle

- Only a deterministic check can pass an item: a test, or a script checking a recorded end state against the Expected outcome. Judgement, an agent's or a model's, can only lower a verdict to fail or unknown.
- "Unknown" counts as a fail. False alarms are tolerable; false passes are not.

## Before any code

1. Feature file: copy `templates/feature.md` to `docs/features/<feature>.md` and fill ID, Rev, Item, Entry point and Expected outcome. IDs are short, like `F3-2`, and never reused. Bump an item's Rev when its Expected outcome changes: the tests linked at the old revision become stale.
2. Coverage check: before coding starts, check that every item has an entry point and a task.
3. Test writer (an experiment; the owner's preference): a fresh agent writes failing entry-point tests from `templates/test-writer-brief.md` and locks them, on the feature's branch. Give it the feature file and `AGENTS.md`, nothing about how the feature will be built.

## Building

4. The implementer's brief (`templates/agent-brief.md`) names the locked tests: it makes them pass and never edits them. It works on the feature's branch from the test writer's commit and pushes only that branch.

## After the implementation, in parallel

5. Trace: a fresh agent from `templates/trace-brief.md` traces each item white-box from the plan and its entry point. It may list the names of the changed files but never reads the diff. Run `scripts/check-citations.sh` on its report at the traced commit; a level line whose citation does not resolve drops to the level below.
6. Black-box test: a fresh agent from `templates/blackbox-test-brief.md` uses the running app and never reads the source. An item passes only on its check script's verdict over recorded backend evidence. Third-party services are mocked by default.
7. Review: a fresh agent from `templates/review-brief.md`, on Opus at xhigh effort for a whole feature or a one-way change. Give it the feature's items and entry points, not the Level column. Experiment (the owner's preference): plant a known bug in a copy of the change first; a review that misses it does not count, and you run it again with a fresh reviewer. Record hit or miss. When the author disputes a finding with evidence, you decide.

## The push gate, on every push

8. `scripts/check-locked-tests.sh` (the locked tests are unchanged), `scripts/check-red-green.sh` (they fail on the code before the feature and pass after it), `scripts/check-test-count.sh` (the runner finished and no test was lost) and `scripts/check-trace-links.sh` (the trace links hold; or the OpenFastTrace trace). The project's `AGENTS.md` lists them in its gate.

## Hardening, once per feature

9. A different agent runs `templates/hardening-brief.md`, with diff-scoped mutation testing on the changed lines (for StrykerJS, `scripts/stryker-mutate-ranges.sh` gives the ranges). Mutation testing also runs in scheduled CI, not on every push.
10. No unexplained surviving mutant on the changed lines. Agents only propose skips; a proposed skip counts as unknown, which blocks like a fail, until the owner approves it. Findings become a follow-up change.

## Shipping

11. Walkthrough: the owner watches the feature work before it ships. Record it in the feature file's `Walkthrough:` line only on the owner's word: `done YYYY-MM-DD at <commit>`, or `skipped YYYY-MM-DD at <commit>: <reason>`, where a skip needs a written reason. Skipping is generally a bad idea, even in a hurry. A Rev bump or a new item after the commit named makes the walkthrough or skip stale. `hooks/check-walkthrough`, run by the pre-push hook, refuses the push until it is in order.
12. Merge: once the walkthrough is recorded on the feature's branch, merge it to `main` and push (a showcase project: on the owner's word, through its pull request). The walkthrough check acts only once every item is `functional`, so the branch, not the hook, is what keeps a feature with a lowered Level off `main`.
13. A showcase project that squash-merges fetches pull-request refs, so the commit a walkthrough names stays findable (`rules/setup.md`).

## Choices per project

- Traceability: the light check (item tags in test names, `scripts/check-trace-links.sh`) is the default and runs in every project with feature files. A showcase project also traces with OpenFastTrace (`templates/openfasttrace.md`), accepting its Java 17 dependency: the owner chose to learn it now in a showcase project (D91), and it is that project's tier 2 bonus.
- Agent-driven UI runs (the owner's preference): before each release while a project has no users, on a schedule once it has users, never on finished or abandoned projects. Their cost is decided later.
- Testing tools are your call; put a choice to the owner only when there is a real trade-off.
- Session recordings (the Entire trial) are part of no verification step: a missing record proves nothing.
- A bug that got past these steps goes to `docs/escapes.md`, with the step that should have caught it (the `coordinating` skill).
