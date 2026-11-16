# Review brief: <PR #n or change title>

<!-- For a cold reviewer: a fresh agent with none of the author's
     conversation. Give it the task as it was given to the author, never
     the author's account of what was done. For a feature, add the items
     from its feature file but not the Level column: levels are the
     trace's account of the work. Run whole-feature reviews and reviews
     of one-way changes at effort: "xhigh". -->

<!-- Experiment, started 2026-11-16: a planted bug (D80). Before the
     review, the coordinator copies the change to a branch, plants one
     known bug in it (a flipped comparison, a dropped check, a wrong
     default), and gives the reviewer that branch without saying so: fill
     "What to read" with the copy branch as a solo change, and "Verdict"
     with a file to write, for a pull request too, so that no finding
     about the planted bug reaches the real PR. A review that misses the
     bug does not count: at most one rerun, with a fresh reviewer; after
     a second miss, tell the owner. Record each run as a row of
     <project>/metrics/review-canary.md in the private repository (the
     table: templates/review-canary.md). The other findings apply to the
     real change: post them there yourself, without the planted bug's.
     Delete the copy branch afterwards; the real change merges from its
     own. -->

You are reviewing a change you did not write. Read it cold and decide whether it is ready.

## The task the author was given

<Paste the goal and scope from the author's brief, or link the issue.>

Feature items: <paste the Item, Entry point and Expected outcome columns from `docs/features/<feature>.md`, or delete this line>.

## What to read

- Project rules: `AGENTS.md` and the shared working agreements it points to.
- The diff, from git objects rather than the working tree (someone else may be editing it):
  - Pull request: `gh pr diff <n>` and `gh pr view <n>`.
  - Solo change: `git fetch origin && git diff origin/main...<branch-or-sha>`, and `git log origin/main..<branch-or-sha>` for the messages.
- Any file the diff touches, at the reviewed commit: `git show <sha>:<path>`.

## What to check

1. Does it do what the task asked, and nothing it was told not to do?
2. Correctness: logic errors, edge cases, error handling, concurrency, off-by-one, time zones, money and rounding.
3. Tests: were they written first for logic and bug fixes? Would a wrong line still pass? Was any test weakened, skipped or deleted?
4. Security: input validation, secrets, injection, permissions.
5. Fit: follows the project's rules, layout and existing patterns; no dead code or stray debug output.
6. Function shape, both ways: each function does one thing at one level of detail. Too big: over the linter's limits (`templates/function-limits.md`) without a stated reason. Too split: a single-use helper that only passes its arguments on, or a name that hides no real detail; fold it back in.
7. Commits: Conventional Commits, one logical change each, bodies that say why.

Run the gate yourself if you can (`<command>`); report what you ran. Do not edit files or push.

## Verdict

Post it where the author will see it. For a pull request: `gh pr review <n> --comment --body-file <file>`. <Or: write it to <file> and post nothing; delete the option that does not apply.>

```text
Verdict: ready | changes needed

Findings
1. [blocker] path/to/file.ts:42 - what is wrong, why it matters, a suggested fix
   evidence: <the scenario that fails: input or steps, expected, actual>
2. [major] ...
3. [minor] ...
4. [nit] ...

Checked: <what you ran or read>. Not checked: <what you could not>.
```

Severity: **blocker** (wrong behaviour, data loss, security hole, broken build), **major** (a real bug in a less common path, a missing test for new logic), **minor** (clarity, small robustness gaps), **nit** (style; never blocks). "Ready" means no blockers or majors.

Every finding carries its evidence: file:line and, above a nit, a scenario that fails. The author may dispute a finding with counter-evidence; the coordinator settles it.
