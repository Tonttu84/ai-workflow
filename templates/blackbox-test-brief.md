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
- Background: <the facts you need, each marked `(checked: <source>)` or `(memory)`, and the owner's words with their level and date: Owner (instruction, 2026-11-16): "...". Or none.>

If you cannot get the app running with these, say what you tried and what failed, and stop. Do not read the code to work around it.

## For each item

1. Write a check script for its expected outcome, before you act: it reads recorded backend evidence (the database state, the stored file, the logged request or sent mail) and exits 0 only when the expected outcome holds. Run it now: it must fail, since nothing has happened yet. A check that passes before the action proves nothing; fix it.
2. Do the item from its entry point (browser, CLI or API).
3. Run the check script again. Only its pass makes the item `pass`. Your own account, the page you saw and the screenshots are evidence for the report: they can turn a pass into `fail` or `unknown`, never make one. If you cannot write or run the check, the result is `unknown`, and `unknown` counts as a fail.
4. Then try what a user would hit: empty and huge input, bad input, a double submit, going back, a refresh, steps in the wrong order. <Add the cases that matter for this feature.>

Keep the evidence for each check: the check script, its output before and after, the steps, expected against actual, and a screenshot or a command-output file under <scratch folder>, named `<project>-<feature>-<item>-<n>.png` (or `.txt`, `.sh`).

## Goal-only run (optional)

<Delete this section unless the coordinator asks for it.> A second run, in a fresh session, given only each item and its expected outcome, not the entry point: can a user find the way? Its result is a separate discoverability report (found or not, the steps tried, where you got lost), never part of pass or fail, since a miss mixes "broken" with "not found".

## Rules

- Change no file in the repository and commit nothing.
- Use the project's test data and test accounts, never real ones; no real payments or messages.
- Third-party services (payments, email, maps) are mocked. Use a provider's test mode only where `AGENTS.md` names it, and only one built for automated runs.
- Every command and wait has a deadline.

## Report

Per item:

```text
<ID> <item>: pass | fail | unknown
  check: <script path>; before the action: exit <n>; after: exit <n>
  steps: 1. ... 2. ...
  expected: <the expected outcome>   actual: <what the evidence shows>
  evidence: <paths>
```

Then the findings, each with a reproduction (steps, expected, actual, evidence path) and a severity: **blocker** (the item does not work, data is lost, a security hole), **major** (it fails on a less common path), **minor** (a rough edge: an unclear message, a small glitch), **nit** (cosmetic; never blocks).

Last:

- Decisions you made between real alternatives, one per line in the format of `docs/decisions.md`: `<decision> | <reason> | <chosen against> | YYYY-MM-DD · agent · <evidence> · <one-way or two-way>` (`agent under Dn` when it falls within decision Dn), or none.
- Assumptions you could not verify, one per line: `<assumption> | <why it matters>; <why it could not be checked> | — | YYYY-MM-DD · agent · assumed · two-way`, or none.
