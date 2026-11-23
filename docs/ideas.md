# Ideas

Improvements to the workflow left for later on purpose. Each entry says where it came from, why it waits and what would make it worth revisiting. An idea that is taken up becomes a decision row in `docs/decisions.md` and keeps its entry here, marked with that row's ID; one that is dropped keeps its entry too, marked with the reason. This file is public: keep entries generic, with no project names, private paths or accounts.

## 1. Formal verification

- Date: 2026-11-17
- Source: https://www.anthropic.com/research/formal-verification (Anthropic's Frontier Red Team with Theorem, 2026-10-22). Claude proved that 239 fuzz-test entry points across 123 open-source libraries from OSS-Fuzz never crash on any input under 64 MB, in Rocq, turning each existing fuzz test into a specification; it also built a Python interpreter in Rust and proved it against a published CPython semantics with Verus. Owner (idea, 2026-11-17): "This would be ideal way to do AI software but Im a bit skeptical if we can add this now".
- What: prove properties of a project's critical code instead of only testing them, with the specifications drawn from what the workflow already writes down.
- Why not now: the cost is at an organisation's scale (a proof can take hundreds of millions of tokens); the work rested on a prebuilt RISC-V and Linux machine model; and the post itself says "formally verified" is not "bug-free": a proof is only as good as its specification and its machine model.
- Revisit when: a Rust project has a small, critical core that Verus could cover, or proof costs drop. A first step that needs no prover: turn the locked tests and the feature files' Expected outcomes into written specifications.

## 2. The metrics script

- Date: 2026-11-17
- Source: D96 (the records stay machine-parseable; a metrics script comes later).
- What: a script that counts the decision rows, the escapes and the planted-bug review results across projects and reports them as counts.
- Why not now: the records are too few to say anything yet, and a script written before the first real numbers would guess at the questions.
- Revisit when: a few projects have kept the records for some weeks, or the owner asks a question the records could answer.

## 3. A per-test baseline in check-test-count

- Date: 2026-11-17
- Source: `scripts/check-test-count.sh`, which compares one number per report.
- What: keep the names of the tests each report ran, so that a deleted test is seen even when a new test in the same report keeps the count the same.
- Why not now: the count already catches a test lost on its own, and the locked tests are guarded by `check-locked-tests.sh`; a name list needs a committed baseline that changes with every renamed test.
- Revisit when: an escape shows a test swapped for another in the same change, or a renaming churn is cheap to record.

## 4. A check that a feature file's Rev matches its OpenFastTrace revision

- Date: 2026-11-17
- Source: `templates/openfasttrace.md` ("Nothing checks yet that the table's Rev and the OFT revision agree").
- What: a script that fails when an item's Rev in the feature table and the revision of its `feat~<id>~<rev>` ID differ.
- Why not now: OpenFastTrace runs in one showcase project only (D117), which has not started; until then review compares them.
- Revisit when: that project starts, or a mismatch gets past a review.

## 5. Per-testcase red-green from JUnit output

- Date: 2026-11-17
- Source: `scripts/check-red-green.sh`, which runs each locked test file as a whole.
- What: read the JUnit report of each run, so that every locked testcase, not only every file, must fail before the feature and pass after it; a vacuous test next to a real one in the same file would then be caught.
- Why not now: it needs each stack's runner to write a report for a single-file run, and the hardening step's mutation run already finds tests that check nothing.
- Revisit when: an escape shows a vacuous locked test that shared a file with a real one.

## 6. Research: simpler languages for agent work

- Date: 2026-11-17
- Source: one practitioner's report of agents struggling to write and fix Rust tests.
- What: research whether a simpler language such as Go suits agent-written services better than Rust (the stack proposal's compiled default), by how often agents get code and tests right and how fast the loop is.
- Why not now: one report is an anecdote, and no project is waiting on the choice.
- Revisit when: the next compiled-language project is planned, or the escapes log shows agents repeatedly failing on one language.

## 7. Tamper-resistant records for tier 2

- Date: 2026-11-17
- Source: D59 and D99 (tier 2 audit evidence; tamper-resistant records are not yet defined).
- What: records of what was checked (gate runs, reviews, walkthroughs) that an agent or a later edit cannot quietly change, such as signed commits or CI attestations.
- Why not now: tier 1 guards against forgetting and a false "done", not against tampering, and no showcase project needs audit evidence yet.
- Revisit when: a showcase project is meant to show audit evidence to someone outside, or a record is found changed after the fact.

## 8. A CI workflow template for the gate and the deferred mutation run

- Date: 2026-11-17
- Source: D100, confirmed by the owner in D116; the second docs review (no CI template runs `check-features.sh`); D129, whose required CI job in a showcase project with feature files is the gate half of this idea.
- What: a workflow template that runs `.ai-workflow/check-features.sh --base origin/main` with full history, and the scheduled diff-scoped mutation run of D75.
- Taken up, the gate half: D137 (2026-11-18), as `templates/feature-check.yml`. The mutation half still waits.
- Why not now: for the mutation half, a mutation run depends on the stack, and private repositories' Actions minutes are scarce (D39); a template written before a project needs it would be a guess.
- Revisit when: the first project with feature files sets up its CI (recheck 2027-02-16); that project writes the mutation workflow and it becomes the template. The first candidate is the first showcase project with feature files, which sets up the gate's CI job at setup (D129).

## 9. A file-length limit

- Date: 2026-11-23
- Source: a hackathon organiser's engineering rules (D181): no hand-written source file over 600 lines, checked by a script in the gate, with generated code, migrations and tests left out.
- What: a limit on the length of a hand-written source file, beside the function limits of `templates/function-limits.md`, so that a file is split by responsibility before it is too long to review.
- Why not now: the function limits are still a first guess that no project has measured, and a file limit needs a check for each stack: a linter rule where one exists, a script of ours elsewhere. Which linters have one is not checked.
- Revisit when: a review or a walkthrough stalls on a file too long to read, or the function limits have been measured on real projects and made errors.

## 10. A coverage floor on logic

- Date: 2026-11-23
- Source: the same rules (D181): at least 60 % of lines, functions, branches and statements covered in the logic folders, with UI pages not counted. `docs/research/test-strength.md` (option C) rates changed-line coverage as cheap and gateable, but as finding code no test reaches, not weak assertions.
- What: a coverage floor in the gate, on a project's logic folders or on the changed lines, so that code no test reaches is seen.
- Why not now: new logic is written test first, and the hardening step's mutation run on the changed lines checks the same code more strictly (D75, D76). A floor would mostly measure old code, and a number invites tests written to reach it.
- Revisit when: a migrated project has old logic that no test reaches, or an escape shows untested code that got past the review and the hardening.
