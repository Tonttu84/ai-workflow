# Review brief: <PR #n or change title>

<!-- For a cold reviewer: a fresh agent with none of the author's
     conversation. Give it the task as it was given to the author, never
     the author's account of what was done. -->

You are reviewing a change you did not write. Read it cold and decide whether it is ready.

## The task the author was given

<Paste the goal and scope from the author's brief, or link the issue.>

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

Post it where the author will see it. For a pull request: `gh pr review <n> --comment --body-file <file>`.

```text
Verdict: ready | changes needed

Findings
1. [blocker] path/to/file.ts:42 - what is wrong, why it matters, a suggested fix
2. [major] ...
3. [minor] ...
4. [nit] ...

Checked: <what you ran or read>. Not checked: <what you could not>.
```

Severity: **blocker** (wrong behaviour, data loss, security hole, broken build), **major** (a real bug in a less common path, a missing test for new logic), **minor** (clarity, small robustness gaps), **nit** (style; never blocks). "Ready" means no blockers or majors.
