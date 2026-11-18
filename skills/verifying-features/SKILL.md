---
name: verifying-features
description: The coordinator's pipeline for a user-visible feature in a project whose AGENTS.md uses feature files, from the feature items written before any code, through locked tests, the trace, the black-box test and the review, to hardening with mutation testing, the push gate and the owner's walkthrough. Use it whenever you, as the coordinator, plan, build, review, harden or ship a feature, set up the feature checks in a project, or decide on agent-driven UI runs. Err toward using it too often rather than too rarely. Subagents follow the brief they are given instead.
---

# Verifying features

For the coordinator. Each step's agent gets its template, which carries the rules it needs; the paths here are in the ai-workflow clone. Whether a project uses feature files, and its entry points, outcome evidence, traceability and UI runs, are in its `AGENTS.md`.

A feature's work stays on its own branch from the feature file to the walkthrough, in a solo project too (the owner's instruction, D98): the feature file is the branch's first commit. A change that adds or revises a feature item is feature work, on a branch of its own; other bug fixes and small changes keep the normal solo flow. The local gate, with the feature checks, runs only before a push to `main` or the merge of a pull request, and the hook checks the walkthrough only on a push to `main` (the owner's instructions, D114, D128). A push to another branch needs only the commit check, so push the branch at any time, for backup and review fixes, even while its locked tests are red. It reaches `main` only after the trace, the black-box test, the review, the hardening and the walkthrough, and then you merge and push.

## The principle

- Only a deterministic check can pass an item: a test, or a script checking a recorded end state against the Expected outcome. Judgement, an agent's or a model's, can only lower a verdict to fail or unknown.
- "Unknown" counts as a fail. False alarms are tolerable; false passes are not.

## Before any code

1. Feature file: copy `templates/feature.md` to `docs/features/<feature>.md` and fill ID, Rev, Item, Entry point and Expected outcome. IDs are short, like `F3-2`, and never reused. Bump an item's Rev when its Expected outcome changes: the tests linked at the old revision become stale. Commit it as the first commit of the feature's branch, from a freshly fetched `main`. An unfilled copy of the template fails both `check-features.sh` and the walkthrough hook.
2. Coverage check: before coding starts, check that every item has an entry point and a task.
3. Test writer (an experiment; the owner's preference): a fresh agent writes failing entry-point tests from `templates/test-writer-brief.md` and locks them, on the feature's branch. Give it the feature file and `AGENTS.md`, nothing about how the feature will be built. It runs on every feature while the experiment lasts: every feature file with items needs a `Locked tests: <paths> at <SHA>` line, with no opt-out (the owner's instruction, D115), and each item's Test cell starts with its test file.

## Building

4. The implementer's brief (`templates/agent-brief.md`) names the locked tests: it makes them pass and never edits them. It works on the feature's branch from the test writer's commit and pushes only that branch.

## After the implementation, in parallel

5. Trace: a fresh agent from `templates/trace-brief.md` traces each item white-box from the plan, which is the feature file (its items, entry points and expected outcomes), starting at each entry point. It may list the names of the changed files but never reads the diff. Run `scripts/check-citations.sh --rev <traced SHA> <report>` on its report: it reads only files committed at that SHA, so a citation of ignored code (`node_modules/`) fails. A level line whose citation does not resolve drops to the level below.
6. Black-box test: a fresh agent from `templates/blackbox-test-brief.md` uses the running app and never reads the source. An item passes only on its check script's verdict over recorded backend evidence. Third-party services are mocked by default.
7. Review: a fresh agent from `templates/review-brief.md`, on Opus at xhigh effort for a whole feature or a one-way change. Give it the feature's items and entry points, not the Level column. Experiment (the owner's preference): plant a known bug in a copy of the change first (the review brief's opening comment); a review that misses it does not count. Run it again at most once, with a fresh reviewer; after a second miss, tell the owner. Record each run in `<project>/metrics/review-canary.md` in the private repository (`templates/review-canary.md`). The reviewer writes its verdict to a file; you post the findings on the pull request (`gh pr review --comment`), without the planted bug's. When the author disputes a finding with evidence, you decide.

## The push gate, before work reaches `main`

8. `.ai-workflow/check-features.sh --base origin/main` (the branch the work merges into), in the project's gate, as its `AGENTS.md` lists it; the gate runs before a push to `main` or the merge of a pull request, and a push to another branch skips it. `hooks/install.sh --gate` copies it and the checks it runs into the project's `.ai-workflow/`, and the committed `feature-checks.conf` gives the project's commands (`rules/setup.md`). For every `Locked tests:` line of every feature file it runs `check-locked-tests.sh` (the locked tests are unchanged) and `check-red-green.sh` (they fail on the code before the feature and pass after it), and checks that each item's Test cell starts with a committed file under a locked path that carries the item's tag at its Rev; then the whole test run, `check-test-count.sh` (the runner finished and no test was lost) and `check-trace-links.sh` (every item has a test that ran and passed). A project on OpenFastTrace adds its trace. The lock checks need full history: a shallow clone or CI checkout dies with "unknown commit" (`rules/setup.md`). The pre-push hook checks walkthroughs only on pushes to `main` and to the default branch, which it takes from `refs/remotes/origin/HEAD` (a stale or odd record there can only add checks); where that is not recorded (a repository created with `gh repo create --source . --push`), it checks every branch pushed until `git remote set-head origin --auto` runs once, and tags are always checked.

## Hardening, once per feature, before the merge

9. On the feature's branch, a different agent runs `templates/hardening-brief.md`, with diff-scoped mutation testing on the changed lines (for StrykerJS, `.ai-workflow/stryker-mutate-ranges.sh` gives the ranges). Mutation testing never runs on every push. D75 also has it run in scheduled CI; that job is deferred until the first project with feature files sets up its CI (D100, confirmed by the owner in D116), so today it runs here only.
10. No unexplained surviving mutant on the changed lines. Agents only propose skips; a proposed skip counts as unknown, which blocks like a fail and holds the merge until the owner approves it (D76). Findings become a follow-up change on the feature's branch, before the merge.

## Shipping

11. Walkthrough: the owner watches the feature work before it ships. Record it in the feature file's `Walkthrough:` line only on the owner's word: `done YYYY-MM-DD at <commit>`, or `skipped YYYY-MM-DD at <commit>: <reason>`, where a skip needs a written reason. Skipping is generally a bad idea, even in a hurry. A Rev bump or a new item after the commit named makes the walkthrough or skip stale. `hooks/check-walkthrough`, run by the pre-push hook, refuses a push to `main` until it is in order.
12. Merge once the hardening is done and the walkthrough is recorded on the feature's branch. The walkthrough check acts only once every item is `functional`, so the branch, not the hook, is what keeps a feature with a lowered Level off `main`.
    - Solo: merge the branch to `main`, run the gate and push.
    - Showcase: merge through the pull request, on the owner's word. A merge on GitHub runs no local hook, so the project's required CI check runs the feature checks and the walkthrough check on the pull request (D129, `templates/feature-check.yml`, `rules/setup.md`).
      - At the top of the repository, run `git fetch origin` and `gh pr checkout <number>`. Merge only a head that contains the current `main` (`git merge-base --is-ancestor origin/main HEAD`); otherwise update the branch and run the checks again. Run the gate there, with `.ai-workflow/check-features.sh --base origin/main`.
      - Until that job exists, and always in a private repository, which writes no job, also run the walkthrough check. Where the hooks are in `.githooks/` (the default install, or `--copy-only` under husky), run `bash .githooks/check-walkthrough HEAD`. Where they were installed with `--git-hooks`, run `bash "$(git rev-parse --git-path hooks)/check-walkthrough" HEAD`, which finds them in a linked worktree too, where `.git` is a file.
      - Merge only if all pass, and only the commit you checked: `gh pr merge <number> --squash --match-head-commit "$(git rev-parse HEAD)"`.
13. A showcase project that squash-merges fetches pull-request refs, so the commit a walkthrough names stays findable (`rules/setup.md`).

## Choices per project

- Traceability: the light check (item tags in test names, `.ai-workflow/check-trace-links.sh`) is the default and runs in every project with feature files. OpenFastTrace is learned in one showcase project the owner chooses (D91, D117), on top of the light check (`templates/openfasttrace.md`), accepting its Java 17 dependency; it is that project's tier 2 bonus. Other projects use the light check alone.
- Agent-driven UI runs (the owner's preference): before each release while a project has no users, on a schedule once it has users, never on finished or abandoned projects. Their cost is decided later.
- Testing tools are your call; put a choice to the owner only when there is a real trade-off.
- Session recordings (the Entire trial) are part of no verification step: a missing record proves nothing.
- A bug that got past these steps goes to `docs/escapes.md`, with the step that should have caught it (the `coordinating` skill).
