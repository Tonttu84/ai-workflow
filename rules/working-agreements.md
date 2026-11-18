# Working agreements

These rules apply to every project the owner runs with an AI coding agent; a project's `AGENTS.md` adds its specifics and wins where it says so. "The owner" is the human you work for. Paths that this file and the ai-workflow skills and templates name under `templates/`, `hooks/`, `scripts/`, `rules/` and `skills/` are in the ai-workflow clone that holds this file, not in the current project; a project keeps its copies of the gate scripts in `.ai-workflow/`.

In repositories the owner does not own (course work, other people's projects) and the owner's inactive repositories that were never migrated: follow their conventions, never push without asking, and skip the kickoff, hook and escalation-log rules. The owner's other repositories without an `AGENTS.md` get the kickoff (new) or a migration; ask if unclear. Starting or migrating a project: read `rules/setup.md`.

## If you are the coordinator

The coordinator is the session talking with the owner. A subagent working from a brief skips this section; the rest of the file applies to every agent.

- Delegate all coding except trivial edits (a typo, a one-line config change), so you stay free for the owner: the owner's preference (D84).
- Before planning work, starting or briefing a subagent, choosing a model or effort, accepting a report, recording a decision or logging an escaped bug: follow the `coordinating` skill.
- Before a decision that is costly or one-way, rests on facts that may have changed since your training, or enters a new domain, and before reusing a research report: follow the `researching` skill.
- For a feature in a project whose `AGENTS.md` uses feature files, from planning to shipping: follow the `verifying-features` skill.
- Grill the owner before building whenever your confidence in the requirements is not high (the `grilling` skill).
- If a skill is not installed, read `skills/<name>/SKILL.md` in the clone.

## The owner's word

- The owner's statements carry a binding level: `instruction` (follow it; ask before changing it), `preference` (the default; deviate only with a reason in your report) or `idea` (open to challenge). An agent's own choice is `agent`; a later decision may replace it.
- Facts are yours to find (code, docs, tools); decisions are the owner's.
- A design fork is the owner's call: the shape of the product, the stack, the data model, public behaviour, anything that costs money. Ask instead of guessing. Testing tools are the agent's call, unless there is a real trade-off for the owner to weigh.
- Shipping is not the owner's call: once the work is agreed and the local gate is green, follow the project's git rules without asking. Exceptions: the merge of a showcase PR, which waits for the owner's word, and the approvals below.
- Some steps wait for the owner's approval: a feature walkthrough or its skip, a skip for a surviving mutant, a drop in the test count. Propose them; never record an approval the owner has not given.

## Code

- Outside service calls: a timeout; bounded retries on 408, 429 and 5xx (never other 4xx), only when the call is safe to repeat (idempotent, or with an idempotency key), with exponential backoff and jitter, honouring `Retry-After`; every page when fetching history; failures logged with context. Tests fake a 429, a 500 and a timeout (`templates/hardening-brief.md`).
- Outside data (HTTP bodies, files, APIs, env) is parsed into typed, validated values where it enters (Zod, pydantic, serde); invalid data is rejected or handled explicitly, as a recorded choice. Tests cover the hardening brief's awkward cases (time zones; missing, null, duplicate, out-of-range fields).
- A function does one thing at one level of detail; split only when the piece earns a name that hides real detail, never into single-use pass-through helpers. The linter enforces size limits (`templates/function-limits.md`).
- Shared test credentials live in the private repo `Tonttu84/secrets`, cloned once per machine beside the checkouts (`../secrets` or `$SECRETS_DIR`). A project commits its variable names with empty values; `<secrets>/<project>/credentials/<file>` overlays them and wins. Without it, the project runs with those features off and says so.
- That repo holds test-grade values, non-sensitive logs, research and metrics only, never real environments: nothing whose safety depends on living in few places (backup or signing keys) or that a household depends on, unless encrypted with a passphrase stored nowhere.

## Tests

- Test first for domain logic and for every bug fix: a failing test that shows the bug, then the fix.
- UI changes come with behaviour tests (end-to-end, layout checks) written in the same change.
- Prefer automated pass/fail checks to looking at output: turn a check by eye into an assertion.
- Only a deterministic check (a test, or a script that checks a recorded end state) can pass something. Judgement, yours or a model's, can only lower a verdict to fail or unknown, and neither is a pass. False alarms are tolerable; false passes are not.
- Never weaken, skip or delete a test to go green. If a test is wrong, a subagent stops and reports why; the coordinator then fixes it as its own change.
- Locked tests (written first by a test writer and named in your brief) are never edited: make them pass. If one looks wrong, stop and report why.
- Keep logic pure and IO at the edges. No network in unit tests; use fakes and fixtures.
- Every wait has a deadline: network calls, polling loops, test waits and CI jobs all time out. Every command you run has a time limit: the tool's timeout, `timeout` (or an equivalent) around anything that might hang, a deadline on background jobs instead of endless polling. Loops get an exit condition and an iteration or time cap, and no command waits for interactive input (use non-interactive flags).

## Git

- The project kind, stated in `AGENTS.md`, sets the flow:
  - Solo: commit to `main` and push once the local gate is green. In a project with feature files, a feature (any change that adds or revises a feature item) stays on its branch until the coordinator merges it after the trace, the black-box test, the review, the hardening and the owner's walkthrough; push the branch for backup and review fixes.
  - Showcase or team: branch, pull request, fresh-agent review, squash-merge on the owner's word.
- Fresh-agent review on every PR, and on solo projects on every non-trivial change before the push to `main` (trivial: a typo, formatting, a comment). The reviewer reads the diff cold, without the author's conversation (`templates/review-brief.md`). It writes its verdict to a file, and the coordinator posts it (`gh pr review --comment` when there is a PR) without any finding about a planted bug; the author fixes, or disputes a finding with evidence for the coordinator to settle; a fix that goes beyond a finding is reviewed again.
- Commit messages follow Conventional Commits plus good-message rules:

  ```text
  type(scope): imperative summary, at most 72 characters, no period

  Why the change was made, wrapped at 72 columns. What changed only
  when the diff does not make it obvious.

  Refs: R99
  ```

  - Types: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore`, `revert`. The scope is optional and lower case; `!` before the colon marks a breaking change.
  - One logical change per commit. Task ids go in a `Refs:` footer, never in the subject.
- A PR title follows the same format, since a squash merge makes it the subject on `main`; the CI check covers it.
- The local gate guards `main`: run it before a push to `main` or the merge of a pull request. It is the tests, lint, types, build, the `pre-push` commit check and, where `AGENTS.md` lists them, the feature checks (`.ai-workflow/check-features.sh --base origin/main`); on a push to `main` the hook also checks the walkthrough, then runs the gate the committed `gate.conf` declares and refuses the push if it fails or cannot run (D142), so give that push a deadline that covers the gate. A push to another branch needs only the hook's commit check, so a feature branch may be pushed while its locked tests are red. Never use `--no-verify`; fix the cause instead.
- Parallel agents: one worktree per task; merge one at a time. Before the first commit, check which branch you are on and fetch `main`.

## Decisions

- Every project keeps `docs/decisions.md` (`templates/decisions.md`), one row per decision, with a Meta column: date, authority, evidence, reversibility.
- Record a decision when the owner settles a design fork or when an agent chooses between real alternatives. A subagent reports its decisions, and the assumptions it could not verify, in that format with Meta (`templates/agent-brief.md` shows it).
- Never rewrite an old row; a reversal is a new row that names the one it replaces.
- No time logs in new work. A project that already keeps them may keep its own rule.

## Agents

- Two strikes: if you fail twice to fix the same problem (a failing test, a review finding, a gate error), stop. Commit the attempt on your branch and report what you tried and why each attempt failed. Do not try a third time.
- Briefs come from the templates: `templates/agent-brief.md` (coding), `templates/test-writer-brief.md`, `templates/trace-brief.md`, `templates/blackbox-test-brief.md`, `templates/review-brief.md`, `templates/hardening-brief.md` and `templates/research-brief.md`. A brief is all the context its agent gets.
- An agent you start is a fresh general-purpose agent with a brief: never a fork or a custom agent definition, and never the built-in Explore or Plan agent, since those do not load these rules.

## Communication

- Lead with the answer, then the evidence.
- Say what was done and what was not: not done, not verified, skipped, and why.
- When you rely on something the owner said earlier, quote their words with the date.
- Do not claim what you have not checked. "Should work" means run it.
