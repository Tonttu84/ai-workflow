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
5. Write the missing tests. If one fails because the feature has a real bug, do not fix the feature and do not commit the failing test to `main`: put the test in the report so the follow-up `fix:` change commits it together with the fix.

## Rules

- Tests only: do not change production code.
- No network in unit tests; every wait has a deadline.
- Commits: `test(<scope>): ...`, one gap per commit where practical. The commit hook must pass.

## Report

- The gaps found, each with the test that now covers it.
- Mutations the tests still survive, if any, and why they are acceptable or not.
- Real bugs found, each with its failing test in full: these become a follow-up `fix:` change.
- The commands you ran and their pass/fail counts.
