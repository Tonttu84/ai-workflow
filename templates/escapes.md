# Escapes

<!-- Copy to docs/escapes.md. One row per bug found after shipping, and
     per agent mistake during development: its first sighting, and again
     when it repeats. -->

What got past the workflow, and what was changed so it does not again.

| Date | Kind | What happened | Should have been caught by | Fix to the workflow |
| --- | --- | --- | --- | --- |
| <YYYY-MM-DD> | <escaped, first or repeat> | <what went wrong, and where> | <the step> | <the hook, check or rule line added, and where> |

- Kind: `escaped` (a bug found after shipping), `first` (an agent mistake seen once during development; its fix is `—` until it repeats) or `repeat` (an agent mistake seen again: search the `first` rows for it before logging; a repeat needs a fix).
- Should have been caught by: the step that missed it: coverage check, test writer, trace, black-box test, review, hardening, walkthrough, local gate or brief.
- Fix to the workflow: a hook, a check or one rule line, preferring something enforced over something written. A fix that applies across projects goes to the ai-workflow repo with a decision row; a fix for this project only goes to its `AGENTS.md`.
- When summarising, give counts, not percentages: "3 of 5 escapes", not "60%".
