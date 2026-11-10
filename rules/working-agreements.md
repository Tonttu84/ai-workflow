# Working agreements

These rules apply to every project the owner runs with an AI coding agent; a project's `AGENTS.md` adds its specifics and wins where it says so. "The owner" is the human you work for. `templates/` and `hooks/` paths are in the ai-workflow clone that holds this file, not in the current project.

In repositories the owner does not own (course work, other people's projects) and the owner's inactive repositories that were never migrated: follow their conventions, never push without asking, and skip the kickoff, hook and escalation-log rules. The owner's other repositories without an `AGENTS.md` get the kickoff (new) or a migration; ask if unclear.

## Coordination and delegation

- The main conversation coordinates: it plans, grills, writes briefs, reviews and merges, and makes only small edits (a typo, a one-line config change).
- Coding, long test runs and review fixes go to subagents. Each gets a self-contained brief (`templates/agent-brief.md`), which is all the context it has.
- A subagent's report is evidence, not a verdict: before telling the owner something is done, re-run the local gate, read the diff and spot-check the claims.

## Models and escalation

- Subagents run on Opus 5.5 at normal effort by default (set in the user settings). Do not pass `model` or `effort` for ordinary tasks.
- Never fork; start a fresh subagent with a brief. A fork inherits the whole conversation and the coordinator's model.
- Escalate on your own judgement when a task is hard: pass `model: "opus"` or `model: "fable"` with `effort: "high"`. These rules are the owner's standing request to set the effort level in those cases.
- Every escalation is explained, because the owner wants to learn what is hard for an AI:
  - In the chat, explain in detail why this task is hard for an AI. Name the concrete difficulty (such as a long chain of dependent steps, an ambiguous spec, or an API newer than the model's training). "It is complex" is not an explanation.
  - Append an entry to `escalation-log.md` in the ai-workflow clone, in its format; the file is public, so keep project details generic. There, `git pull --rebase --autostash`, commit that file only (`git commit -m "docs(escalation): ..." -- escalation-log.md`) and push; if the push is rejected, pull and push again. When the task ends, append its outcome the same way, as a new line (never edit an entry): was the escalation needed?

## Grilling

- Grill before building whenever your confidence in the requirements is not high (the `grilling` skill).
- One question at a time, each with your recommended answer, worded so that "yes" accepts it.
- Facts are yours to find (code, docs, tools); decisions are the owner's.
- A design fork is the owner's call: the shape of the product, the stack, the data model, public behaviour, anything that costs money. Shipping is not: once the work is agreed and the local gate is green, follow the project's git rules without asking. The one exception is the merge of a showcase PR, which waits for the owner's word.

## Kickoff (new project)

1. Grill the owner about the goal, the users, the scope and the kind (solo or showcase).
2. Write `docs/kickoff.md` from `templates/kickoff.md` before any code.
3. The stack is discussed every time. Open with a proposal:
   - Web app: TypeScript (strict), Next.js, Tailwind, Prisma, Zod, Vitest, Playwright.
   - Compiled: Rust first. C++ when the project needs its libraries, a game engine or an embedded toolchain.
   - Python (uv, FastAPI, pydantic, pytest, ruff, pyright strict in the gate and CI) for services, scripts and data work, but not by default when the project would benefit from a compiled language.
4. Set up `AGENTS.md` (stating the kind), a one-line `CLAUDE.md` (`@AGENTS.md`) and `docs/decisions.md` from `templates/`; install the commit hook with `hooks/install.sh`; set up CI with `templates/commit-check.yml` and a ruleset on `main` (see Git).

## Code

- Outside service calls: a timeout; bounded retries on 408, 429 and 5xx (never other 4xx), only when the call is safe to repeat (idempotent, or with an idempotency key), with exponential backoff and jitter, honouring `Retry-After`; every page when fetching history; failures logged with context. Tests fake a 429, a 500 and a timeout (`templates/hardening-brief.md`).
- Outside data (HTTP bodies, files, APIs, env) is parsed into typed, validated values where it enters (Zod, pydantic, serde); invalid data is rejected or handled explicitly, as a recorded choice. Tests cover the hardening brief's awkward cases (time zones; missing, null, duplicate, out-of-range fields).
- A function does one thing at one level of detail; split only when the piece earns a name that hides real detail, never into single-use pass-through helpers. The linter enforces size limits (`templates/function-limits.md`).
- Shared test credentials live in the private repo `Tonttu84/secrets`, cloned once per machine beside the checkouts (`../secrets` or `$SECRETS_DIR`). A project commits its variable names with empty values; `<secrets>/<project>/<file>` overlays them and wins. Without it, the project runs with those features off and says so.
- Test-grade values only: nothing whose safety depends on living in few places (backup or signing keys) or that a household depends on, unless encrypted with a passphrase stored nowhere.

## Tests

- Test first for domain logic and for every bug fix: a failing test that shows the bug, then the fix.
- UI changes come with behaviour tests (end-to-end, layout checks) written in the same change.
- After each feature lands, a different agent runs a hardening pass on its tests (`templates/hardening-brief.md`); findings become a follow-up change.
- Prefer automated pass/fail checks to looking at output: turn a check by eye into an assertion.
- Never weaken, skip or delete a test to go green. If a test is wrong, a subagent stops and reports why; the coordinator then fixes it as its own change.
- Keep logic pure and IO at the edges. No network in unit tests; use fakes and fixtures.
- Every wait has a deadline: network calls, polling loops, test waits and CI jobs all time out. Every command you run has a time limit: the tool's timeout, `timeout` (or an equivalent) around anything that might hang, a deadline on background jobs instead of endless polling. Loops get an exit condition and an iteration or time cap, and no command waits for interactive input (use non-interactive flags).

## Git

- The project kind, stated in `AGENTS.md`, sets the flow:
  - Solo: commit to `main` and push once the local gate is green.
  - Showcase or team: branch, pull request, fresh-agent review, squash-merge on the owner's word.
- Fresh-agent review on every PR, and on solo projects on every non-trivial change before the push (trivial: a typo, formatting, a comment). The reviewer reads the diff cold, without the author's conversation (`templates/review-brief.md`). It posts its verdict (`gh pr review --comment` when there is a PR); the author fixes; a fix that goes beyond a finding is reviewed again.
- Commit messages follow Conventional Commits plus good-message rules:

  ```text
  type(scope): imperative summary, at most 72 characters, no period

  Why the change was made, wrapped at 72 columns. What changed only
  when the diff does not make it obvious.

  Refs: R99
  ```

  - Types: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore`, `revert`. The scope is optional and lower case; `!` before the colon marks a breaking change.
  - One logical change per commit. Task ids go in a `Refs:` footer, never in the subject.
- Enforcement:
  - Before every push, run the local gate: tests, lint, types, build, and the `pre-push` commit check. The hooks come from `hooks/install.sh`, wired into the setup command since a fresh clone has them off; Node projects may use commitlint and husky instead (`templates/commitlint.config.mjs`). Never use `--no-verify`; fix the message instead.
  - CI (`templates/commit-check.yml`) is the gate for commit messages and confirms the local check: public repos on every push and PR; private repos, short of Actions minutes, on PRs, by hand (`workflow_dispatch`) and on a schedule.
  - A ruleset on `main` blocks force pushes and deletion, and in PR-flow repos also requires the check. GitHub Free offers rulesets only on public repos, so private repos have none (a recorded exception).
  - So in a private solo repo: the local gate and `pre-push` before every push, CI by hand and on a schedule, no ruleset.
- A squash merge makes the PR title the subject on `main` (repository setting `squash_merge_commit_title=PR_TITLE`), so it follows the same format; the CI check covers it.
- Dependabot security updates are on in every repo (free on private repos too); version updates follow `templates/dependabot.yml`, except in a repo with nothing to update (such as a private secrets repo).
- Parallel agents: one worktree per task; merge one at a time. Before the first commit, check which branch you are on and fetch `main`.

## Decisions

- Every project keeps `docs/decisions.md` (`templates/decisions.md`), one row per decision.
- Record a decision when the owner settles a design fork or when an agent chooses between real alternatives. Never rewrite an old row; a reversal is a new row that names the one it replaces.
- No time logs in new work. A project that already keeps them may keep its own rule.

## Communication

- Lead with the answer, then the evidence.
- Say what was done and what was not: not done, not verified, skipped, and why.
- When you rely on something the owner said earlier, quote their words with the date.
- Do not claim what you have not checked. "Should work" means run it.
