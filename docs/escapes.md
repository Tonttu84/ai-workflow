# Escapes

What got past the workflow, and what was changed so it does not again. The table and its rules: [`templates/escapes.md`](../templates/escapes.md). This file is public: keep entries generic, with no project names, private paths or accounts.

| Date | Kind | What happened | Should have been caught by | Fix to the workflow |
| --- | --- | --- | --- | --- |
| 2026-11-18 | escaped | ShellCheck findings, 21 of them and 2 errors, reached `main` with the merge of 2026-11-17 (4773747), and the repository's CI stayed red for about 15 hours. ShellCheck was not installed, so the push went ahead with the lint step of the local gate unrun; the coordinator's report said so, and nobody read CI afterwards. It was the fourth time: CI on `main` had failed only at ShellCheck for 338a2d2 and 898f38a (2026-11-10) and b9a41b1 (2026-11-11), fixed in 9ebab0c, 0c48945 and b5adeb5. None of the 21 was a behaviour bug (fixed in 9012fb4, b2a44c5, 047d50b and 3a57c1a). | local gate | `hooks/pre-push` runs the project's declared gate (`gate.conf`) before a push to `main` and refuses the push when the gate fails or cannot run, a missing tool included (D142); ShellCheck installed on the machine. |
