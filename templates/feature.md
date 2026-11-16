# Feature F<n>: <name>

<!-- Copy to docs/features/<feature>.md, one file per feature. The
     coordinator fills ID, Rev, Item, Entry point and Expected outcome
     before any code, and checks that every item has an entry point and a
     task. The test writer fills Test and Locked tests. Only the trace
     agent sets Level. -->

<One or two sentences: what the feature does for the user.>

| ID | Rev | Item | Entry point | Expected outcome | Level | Test |
| --- | --- | --- | --- | --- | --- | --- |
| F<n>-1 | 1 | <one user-visible thing> | <how a user reaches it> | <the end state to check> | — | <test file and name, carrying F<n>-1-r1> |

- ID: `F<feature>-<item>`, such as `F3-2`: the feature's number (features are numbered in the order they are created, from 1) and the item's number in this table (from 1). An ID is never reused: a dropped item's number stays retired, so an old test cannot link to a new item by accident.
- Rev: the item's revision, from 1. Bump it when the item's Expected outcome changes. A bump makes every test linked at the old revision stale: recheck each one against the new outcome, rename it to the new revision (relink it) and lock it again.
- Item: one thing a user can see or do.
- Entry point: how a user reaches it: a screen and control, a command, a route or a public function, whichever the project's `AGENTS.md` names.
- Expected outcome: an end state that can be checked, not a list of clicks. For example: "a CSV with last month's rows is downloaded", "an order row exists with status `paid`", "the confirmation page shows the order number and an email is sent to the buyer". A pass is decided by checking this outcome against recorded evidence (database or backend state, files, requests), never by an agent's own claim that it worked.
- Level, each one building on the one before; write the word alone (`functional`, not `4. functional`), and leave `—` until the item is traced. `hooks/check-walkthrough` fails any other value:
  1. `exists`: the code is there.
  2. `substantive`: it is not a stub or a placeholder.
  3. `wired`: it is imported, registered and called from the entry point, and real data flows through it.
  4. `functional`: its locked test passes and goes through the real path.
- Test: the test's file and name. The name carries the item's tag at its current revision. `scripts/check-trace-links.sh` reads the names from the JUnit reports of the test run: only a test that ran and passed links, never a tag in a comment or in a skipped test:
  - `F3-2-r1` where a name can hold `-` (Vitest and Playwright titles): `test('F3-2-r1 downloads last month as CSV', ...)`.
  - `f3_2_r1` where it cannot (Rust and Python function names): `fn f3_2_r1_downloads_last_month()`, `def test_f3_2_r1_downloads_last_month():`. The mapping: lower case, `-` becomes `_`.
  - A test that covers two items carries both tags. Write tags only in this form: in a test name, or a test file the check scans, it reads `F3-2` without a revision, or any other spelling, as an error.

Locked tests: <paths> at <SHA of the `test:` commit>
<!-- The locked test files or directories, separated by spaces and given
     from the top of the repository, then the SHA of the test: commit;
     tests locked in another commit get a line of their own.
     scripts/check-features.sh checks every such line. -->

Walkthrough:
<!-- Empty until the owner has watched the feature work, or decided not
     to. Then, on the line above, exactly one of:
       Walkthrough: done YYYY-MM-DD at <commit>
         the date, and the SHA of the commit watched
       Walkthrough: skipped YYYY-MM-DD at <commit>: <reason>
         no walkthrough: the date, the SHA of the commit whose items the
         owner decided not to watch, and the reason, which is required
     The pre-push hook (hooks/check-walkthrough, installed with
     hooks/install.sh) checks each commit pushed. While every item is
     `functional`, it refuses the push when that line is missing, empty,
     in neither form (the old 'skipped: <reason>' without a date and
     commit included), names a commit the repository does not have, or
     skips without a reason, and when the walkthrough or skip is stale:
     an item's Rev was bumped, or an item added, after the commit it
     names, so what was watched or skipped is no longer what ships. Then
     walk it again, or record a new skip, at the new commit. -->
