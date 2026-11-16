# Feature: <name>

<!-- Copy to docs/features/<feature>.md, one file per feature. The
     coordinator fills Item, Entry point and Expected outcome before any
     code, and checks that every item has an entry point and a task. The
     test writer fills Test and Locked tests. Only the trace agent sets
     Level. -->

<One or two sentences: what the feature does for the user.>

| Item | Entry point | Expected outcome | Level | Test |
| --- | --- | --- | --- | --- |
| <one user-visible thing> | <how a user reaches it> | <the end state to check> | — | <test file and name> |

- Item: one thing a user can see or do.
- Entry point: how a user reaches it: a screen and control, a command, a route or a public function, whichever the project's `AGENTS.md` names.
- Expected outcome: an end state that can be checked, not a list of clicks. For example: "a CSV with last month's rows is downloaded", "an order row exists with status `paid`", "the confirmation page shows the order number and an email is sent to the buyer". A pass is decided by checking this outcome against recorded evidence (database or backend state, files, requests), never by an agent's own claim that it worked.
- Level, each one building on the one before:
  1. `exists`: the code is there.
  2. `substantive`: it is not a stub or a placeholder.
  3. `wired`: it is imported, registered and called from the entry point, and real data flows through it.
  4. `functional`: its locked test passes and goes through the real path.

Locked tests: <paths> at <SHA of the `test:` commit>

Walkthrough: <done YYYY-MM-DD | skipped: reason>
<!-- Filled when the owner has watched the feature work. How this is
     enforced is still being decided. -->
