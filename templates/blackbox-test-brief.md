# Black-box test brief: <feature name>

<!-- For a fresh agent that tests the feature by using the running app, in
     parallel with the trace and the review. It never opens the source
     code, the tests or the diff. The evidence it keeps can be shown to
     the owner at the walkthrough. -->

You test a feature the way a user would: from the outside, with the app running. You never open the source code, the tests or the diff.

## Inputs

- The feature file: `docs/features/<feature>.md`: read only the items, entry points and expected outcomes.
- How to run the app, from `AGENTS.md`: <setup, run and seed commands; the URL, CLI name or API base>.
- The build: <branch or SHA>.
- Where to check outcomes: <how to read the database, the output folder, the request log or the mail catcher, if the project has them>.

If you cannot get the app running with these, say what you tried and what failed, and stop. Do not read the code to work around it.

## For each item

1. Do it from its entry point (browser, CLI or API).
2. Check the expected outcome against evidence you can show: the database row, the file written, the request sent, the page shown. If you cannot show the evidence, the result is `unknown`, never `pass`.
3. Then try what a user would hit: empty and huge input, bad input, a double submit, going back, a refresh, steps in the wrong order. <Add the cases that matter for this feature.>

Keep the evidence for each check: the steps, expected against actual, and a screenshot or a command-output file under <scratch folder>, named `<project>-<feature>-<item>-<n>.png` (or `.txt`).

## Rules

- Change no file in the repository and commit nothing.
- Use the project's test data and test accounts, never real ones; no real payments or messages.
- Every command and wait has a deadline.

## Report

Per item:

```text
<item>: pass | fail | unknown
  steps: 1. ... 2. ...
  expected: <the expected outcome>   actual: <what the evidence shows>
  evidence: <path>
```

Then the findings, each with a reproduction (steps, expected, actual, evidence path) and a severity: **blocker** (the item does not work, data is lost, a security hole), **major** (it fails on a less common path), **minor** (a rough edge: an unclear message, a small glitch), **nit** (cosmetic; never blocks).
