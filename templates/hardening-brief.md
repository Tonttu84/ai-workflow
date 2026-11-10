# Hardening brief: <feature name>

<!-- For the test hardening run after a feature lands. Give it to an
     agent that did not write the feature. -->

The feature below has landed with its tests. Your job is to attack those tests, not to change the feature: find inputs and mistakes the tests would let through.

## The feature

- What it does: <one paragraph, from the feature's brief>.
- Where it lives: <files or modules>.
- Its tests: <test files>.
- Landed in: <commit range or PR>.

## What to do

1. Read the code and its tests. List the behaviours the tests pin down and the ones they leave open.
2. **Would a wrong line still pass?** For the core logic, change one line at a time (flip a comparison, drop a branch, return early, change a constant) and run the tests. Every change the tests survive is a gap. Put the code back after each try. Use a mutation-testing tool if the project has one.
3. **Edge cases**: empty, one, many; zero, negative, maximum; duplicates; unicode and long strings; time zones and daylight saving; rounding; concurrent calls; errors from every IO edge.
4. **Property tests** where an invariant holds for all inputs (round trips, ordering, conservation of totals, idempotence), with the project's property-testing library.
5. **Outside edges**: if the feature calls a service or takes in outside data, check it against the sections below.
6. Write the missing tests. If one fails because the feature has a real bug, do not fix the feature and do not commit the failing test to `main`: put the test in the report so the follow-up `fix:` change commits it together with the fix.

## Calls to outside services

Each point below must hold in the code and be pinned by a test against a fake (a stub server or a fake client, never the real service), with a fake clock rather than real sleeps:

- **Timeout** on every call. Test: the fake never answers; the call fails within the timeout.
- **Bounded retries on 429 and 5xx**, with exponential backoff, jitter and a cap on each delay. Tests: a 500 every time gives up after the set number of attempts and reports the last error; a 500 then a 200 succeeds.
- **`Retry-After`** (seconds or an HTTP date) is honoured, within the cap. Test: a 429 with `Retry-After: 7` waits 7 seconds on the fake clock, then retries.
- **No retry on other 4xx** (400, 401, 403, 404, 422): one call, then a clear error. A timeout or dropped connection is retried only when the call is safe to repeat.
- **Pagination**: fetching history follows every page (next link, cursor or offset) until the service says there is no more, with a page cap so a cursor that loops cannot run forever. Test: three pages, every item arrives once.
- **Failures logged with context**: the service, the operation, the status, the attempt count and the request id if any; never tokens or personal data.

## Rules

- Tests only: do not change production code.
- No network in unit tests; every wait has a deadline.
- Commits: `test(<scope>): ...`, one gap per commit where practical. The commit hook must pass.

## Report

- The gaps found, each with the test that now covers it.
- Mutations the tests still survive, if any, and why they are acceptable or not.
- Real bugs found, each with its failing test in full: these become a follow-up `fix:` change.
- The commands you ran and their pass/fail counts.
