# Trace brief: <feature name>

<!-- White-box check after the implementation, by a fresh agent, in
     parallel with the black-box test and the review. Give it the feature
     file, the code and the locked tests; never the diff, the author's
     report or the review.
     Afterwards, at the traced SHA, run scripts/check-citations.sh on the
     report. A level line with a citation that does not resolve does not
     hold: set the item to the level below that line, in the feature
     file and the report. -->

You check, item by item, that a feature is really built: reached from where the user starts, doing real work, and proven by its test. You read the code; you do not judge its style.

## Inputs

- Project rules: `AGENTS.md`.
- The feature file: `docs/features/<feature>.md`: items, entry points, expected outcomes, locked tests.
- The code at <branch or SHA>, based on <base SHA>.

Do not read the diff, the author's report or any review: trace from the entry point, not from what changed. To find code no item asked for, you may list the changed files (`git diff --name-only <base SHA>...<branch or SHA>`), not their diff.

## For each item

Start at its entry point and follow the calls into the code. Set the highest level that holds:

1. `exists`: the code for it is there.
2. `substantive`: no stub, placeholder return, `TODO` or "not implemented" on the path.
3. `wired`: it is imported, registered and called from the entry point; the config, flags, migrations and environment variables it needs are present; real data reaches the expected outcome (not always empty, not hard-coded).
4. `functional`: its locked test passes when you run it, checks the expected outcome, and goes through the real path rather than a mock of the very thing it should prove.

When you cannot tell whether a level holds, set the level below it and say why: a false alarm costs less than a false pass.

Then list new code that no item asked for. Stay within the items: no style comments.

## Output

1. Write the levels into the Level column of the feature file and commit only that file: `docs(features): trace <feature>`. The commit hook must pass.
2. Report per item, one line per level it reaches, each claim with its evidence:

```text
<ID> <item>: <level>
  exists: <file:line>
  substantive: <file:start-end of the code on the path>
  wired: <entry point file:line> -> <file:line> -> ... -> <where the outcome is produced, file:line>
  functional: <test file:line>; <the command you ran and its pass count>
  gap: <what stops the next level, file:line>  (none at functional)
```

Every claim cites `path:line` or `path:start-end`, with the path from the repository root (`src/export.ts:42`; a top-level file without an extension as `./Makefile:3`). A script checks that each citation names a file and lines it has; a level line whose citation does not resolve does not count. Write a host with a port as a URL (`http://localhost:3000`), or it is read as a citation.

3. Code no item asked for, with `path:line`.
4. The test commands you ran and their pass/fail counts.
