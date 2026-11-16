# Hardening brief: <feature name>

<!-- For the test hardening run after a feature lands. Give it to an
     agent that did not write the feature. -->

The feature below has landed with its tests. Your job is to attack those tests, not to change the feature: find inputs and mistakes the tests would let through.

## The feature

- What it does: <one paragraph, from the feature's brief>.
- Where it lives: <files or modules>.
- Its tests: <test files>.
- Its feature file: `docs/features/<feature>.md`: items, entry points, expected outcomes and locked tests.
- Landed in: <commit range or PR>; the commit before it (`<base>` below): <SHA>.
- The black-box tester's backend check scripts: <paths, or none>.
- Background: <the facts you need, each marked `(checked: <source>)` or `(memory)`, and the owner's words with their level and date: Owner (instruction, 2026-11-16): "...". Or none.>

## What to do

1. Read the code and its tests. List the behaviours the tests pin down and the ones they leave open.
2. **Would a wrong line still pass?** Run the mutation tool on the lines the feature changed (below). Every surviving mutant is a gap: write the test that kills it, or propose a skip. For logic the tool cannot mutate, change one line at a time by hand (flip a comparison, drop a branch, return early, change a constant), run the tests, and put the code back.
3. **Every check fails on a broken variant**: each check this step relies on (the new tests, and the black-box tester's backend check scripts) must be seen to fail once. Break the code, or the state a backend check reads (a missing row, a wrong status, an absent file), one way it should catch; run the check; record the failing line; put it back. A check never seen failing counts as unknown.
4. **Edge cases**: empty, one, many; zero, negative, maximum; duplicates; unicode and long strings; time zones and daylight saving; rounding; concurrent calls; errors from every IO edge.
5. **Property tests** where an invariant holds for all inputs (round trips, ordering, conservation of totals, idempotence), with the project's property-testing library.
6. **Outside edges**: if the feature calls a service or takes in outside data, check it against the sections below.
7. Write the missing tests. If one fails because the feature has a real bug, do not fix the feature and do not commit the failing test to `main`: put the test in the report so the follow-up `fix:` change commits it together with the fix.

## Mutation run on the changed lines

`<base>` is the commit before the feature. Scratch files go outside the worktree, named `<project>-<feature>-...`.

- Rust (cargo-mutants): `git diff <base> > ../<project>-<feature>.diff && cargo mutants --in-diff ../<project>-<feature>.diff`. Exit 0: every mutant caught; 2: missed mutants; 3: timeouts; 4: the tests already fail. https://mutants.rs/in-diff.html, https://mutants.rs/exit-codes.html
- TypeScript (StrykerJS): `npx stryker run --incremental --reporters clear-text,html --mutate "$(.ai-workflow/stryker-mutate-ranges.sh <base>)"`; the script, copied into the project by the ai-workflow `hooks/install.sh --gate` (or in the clone's `scripts/` where the project has no `.ai-workflow/`), turns the diff into line ranges, since StrykerJS has no diff mode. Stryker's exit status ignores survivors unless `thresholds.break` is set: read them from the clear-text report.
- Python (mutmut 3; on Windows only inside WSL, since it needs `fork`): mutmut has no diff mode, so run it on each function the feature changed, `mutmut run "<module>.<function>*"`. `mutmut results` lists every mutant not killed, `mutmut show <name>` shows one; every one of them counts. https://mutmut.readthedocs.io/en/latest/

The policy: **no unexplained surviving mutant on the changed lines.** A timeout or an untested mutant counts as a survivor. For each one, either add a test that kills it, or propose a skip with the mutant, its line and why no test should kill it (an equivalent mutant, say). You may only propose: a proposed skip counts as unknown and blocks the step like a fail until the owner approves it. Do not add skip annotations yourself. Once the owner approves, the annotation goes in with the reason, the approval and its date:

- Rust: `#[mutants::skip] // equivalent: <reason>; approved by the owner YYYY-MM-DD` (the `mutants` crate as a regular dependency).
- StrykerJS: `// Stryker disable next-line <Mutator>: equivalent: <reason>; approved by the owner YYYY-MM-DD`
- mutmut: `# equivalent: <reason>; approved by the owner YYYY-MM-DD` on the line above, and `# pragma: no mutate` on the line itself.

## Calls to outside services

Each point below must hold in the code and be pinned by a test against a fake (a stub server or a fake client, never the real service), with a fake clock rather than real sleeps:

- **Timeout** on every call. Test: the fake never answers; the call fails within the timeout.
- **Bounded retries on 408, 429 and 5xx** (but not 501, which will not change on a retry), with exponential backoff, jitter and a cap on each delay, **only for a call that is safe to repeat**: idempotent (GET, PUT, DELETE) or carrying an idempotency key. A POST without one is not retried after a 500, 502 or 504, since the first try may already have done its work (a charge, an email). Tests: a 500 every time gives up after the set number of attempts and reports the last error; a 500 then a 200 succeeds; a POST without an idempotency key that gets a 500 is sent once.
- **`Retry-After`** (seconds or an HTTP date) is honoured: never retry sooner than it says. If it asks for longer than the cap on a delay, give up and report the error rather than retrying early. Tests: a 429 with `Retry-After: 7` waits 7 seconds on the fake clock, then retries; one longer than the cap is not retried and the error says why.
- **No retry on other 4xx** (400, 401, 403, 404, 422; 408 and 429 are the exceptions above): one call, then a clear error. A timeout or dropped connection is retried only when the call is safe to repeat.
- **Pagination**: fetching history follows every page (next link, cursor or offset) until the service says there is no more, with a page cap so a cursor that loops cannot run forever. Test: three pages, every item arrives once.
- **Failures logged with context**: the service, the operation, the status, the attempt count and the request id if any; never tokens or personal data.

## Data from outside

HTTP bodies, files, API responses and environment variables are parsed once, where they enter, into typed and validated values (Zod, pydantic, serde or the stack's equivalent); the code behind the boundary never sees raw input. Invalid data is rejected with an error that names the field, or handled explicitly (a default, or skipped with a log line), and `docs/decisions.md` records which. Test each case at the boundary:

- **Timestamps and time zones**: `Z`, other offsets and no offset at all (rejected, or given a zone on purpose); a daylight-saving gap and overlap; epoch seconds against milliseconds; a date near midnight that is another day in UTC.
- **Missing, null and empty**: a missing field, `null`, an empty string and an empty list are four different inputs; an unset variable is not an empty one.
- **Duplicates**: a repeated key in one object, a repeated id or row in a list.
- **Out of range**: zero, negative, too large, `NaN` and infinity, a string past its length limit, an unknown enum value.
- **Wrong types and extras**: a number sent as a string and the other way round; unknown extra fields, ignored or rejected by a recorded choice.

## Rules

- Tests only: do not change production code.
- Leave the locked tests as they are; add new tests beside them.
- No network in unit tests; every wait has a deadline.
- Commits: `test(<scope>): ...`, one gap per commit where practical. The commit hook must pass.

## Report

- The gaps found, each with the test that now covers it.
- The mutation run: the command, the mutants tested, killed and surviving. Each survivor with its line and either the test that now kills it or a proposed skip and its reason.
- Each check and the broken variant it was seen to fail on: what you broke, and the failing line.
- Real bugs found, each with its failing test in full: these become a follow-up `fix:` change.
- The commands you ran and their pass/fail counts.
- Decisions you made between real alternatives, one per line in the format of `docs/decisions.md`: `<decision> | <reason> | <chosen against> | YYYY-MM-DD · agent · <evidence> · <one-way or two-way>` (`agent under Dn` when it falls within decision Dn), or none.
- Assumptions you could not verify, one per line: `<assumption> | <why it matters>; <why it could not be checked> | — | YYYY-MM-DD · agent · assumed · two-way`, or none.
