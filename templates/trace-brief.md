# Trace brief: <feature name>

<!-- White-box check after the implementation, by a fresh agent, in
     parallel with the black-box test and the review. Give it the feature
     file, the code and the locked tests; never the diff, the author's
     report or the review. -->

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
2. Report per item, with file:line evidence:

```text
<item>: <level>
  path: <entry point file:line> -> <file:line> -> ... -> <where the outcome is produced, file:line>
  gap: <what stops the next level, file:line>  (none at functional)
```

3. Code no item asked for, with file:line.
4. The test commands you ran and their pass/fail counts.
