# Working agreements

These rules apply to every project the owner runs with an AI coding agent. A project's `AGENTS.md` adds what is specific to it (its kind, stack, commands, domain rules, quirks) and wins where it says so explicitly. "The owner" is the human you work for.

## Coordination and delegation

- The main conversation is the coordinator. It plans, grills, writes briefs, reviews and merges. Small edits are fine there (a typo, a one-line config change); real work is delegated.
- Coding, long test runs and review fixes go to subagents. Each gets a self-contained brief (`templates/agent-brief.md` in this repo): the goal, files to touch and to leave alone, the tests to write first, the commands that verify the work, and what to report. The brief is all the context the subagent has.
- A subagent's report is evidence to check, not a verdict. Before telling the owner something is done, re-run the gate, read the diff and spot-check the claims.
- Parallel subagents each work in their own git worktree.

## Models and escalation

- Subagents run on Opus 5.5 at normal effort by default (set in the user settings). Do not pass `model` or `effort` for ordinary tasks.
- Never fork. Always start a fresh subagent with a brief. A fork inherits the whole conversation and runs on the coordinator's model, which defeats both the clean brief and the cheaper default.
- Escalate on your own judgement when a task is hard: pass `model: "opus"` with `effort: "high"`, or `model: "fable"` with `effort: "high"`. These rules are the owner's standing request to set the effort level in those cases.
- Every escalation is explained, because the owner wants to learn what is hard for an AI:
  - In the chat, explain in detail why this task is hard for an AI. Name the concrete difficulty (a long chain of dependent steps, an ambiguous or contradictory spec, concurrency, numeric precision, an API newer than the model's training, a large amount of code to hold at once). "It is complex" is not an explanation.
  - Append an entry to `escalation-log.md` in the ai-workflow clone this file is imported from, in the format given there; commit it there and push. When the task ends, fill in the outcome: was the escalation needed?

## Grilling

- Grill before building whenever your confidence in the requirements is not high (the `grilling` skill).
- One question at a time, each with your recommended answer, worded so that "yes" accepts it.
- Facts are yours to find (code, docs, tools); decisions are the owner's.
- A design fork is the owner's call: the shape of the product, the stack, the data model, public behaviour, anything that costs money. Shipping is not: once the work is agreed and the gate is green, follow the project's git rules without asking. The one exception is the merge of a showcase PR, which waits for the owner's word.

## Kickoff (new project)

1. Grill the owner about the goal, the users, the scope and the kind (solo or showcase).
2. Write `docs/kickoff.md` before any code (`templates/kickoff.md`): goal, kind, the stack decision with the alternatives considered, the first decisions, and the agent brief for this project.
3. The stack is discussed every time. Open with a proposal:
   - Web app: TypeScript (strict), Next.js, Tailwind, Prisma, Zod, Vitest, Playwright.
   - Compiled: Rust first. C++ when the project needs its libraries, a game engine or an embedded toolchain.
   - Python (uv, FastAPI, pydantic, pytest, ruff) for services, scripts and data work, but not by default when the project would benefit from a compiled language.
4. Set up `AGENTS.md` (stating the kind), a one-line `CLAUDE.md` (`@AGENTS.md`), `docs/decisions.md`, the commit hook and CI, all from `templates/`.

## Tests

- Test first for domain logic and for every bug fix: a failing test that shows the bug, then the fix.
- UI changes come with behaviour tests (end-to-end, layout checks) written in the same change.
- After each feature lands, a different agent runs a hardening pass on its tests (`templates/hardening-brief.md`): edge cases, property tests, "would a wrong line still pass?". Findings become a follow-up change.
- Prefer automated pass/fail checks over an agent or a human looking at output. If you are checking something by eye, turn it into an assertion.
- Never weaken, skip or delete a test to go green. If a test is wrong, say why and fix it as its own change.
- Keep logic pure and IO at the edges. No network in unit tests; use fakes and fixtures.
- Every wait has a deadline: network calls, polling loops, test waits and CI jobs all time out.

## Git

- The project kind, stated in `AGENTS.md`, sets the flow:
  - Solo: commit to `main` and push once the gate (tests, lint, types, build) is green.
  - Showcase or team: branch, pull request, fresh-agent review, squash-merge on the owner's word.
- Fresh-agent review on every PR, and on solo projects on every non-trivial change before the push (trivial: a typo, formatting, a comment). The reviewer has none of the author's conversation and reads the diff cold (`templates/review-brief.md`). It posts its verdict (`gh pr review --comment` when there is a PR); the author fixes; a fix that goes beyond a finding is reviewed again.
- Commit messages follow Conventional Commits plus good-message rules:

  ```text
  type(scope): imperative summary, at most 72 characters, no period

  Why the change was made, wrapped at 72 columns. What changed only
  when the diff does not make it obvious.

  Refs: R99
  ```

  - Types: `feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore`, `revert`. The scope is optional and lower case; `!` before the colon marks a breaking change.
  - One logical change per commit. Task ids go in a `Refs:` footer, never in the subject.
- A commit hook enforces this in every project: commitlint with `@commitlint/config-conventional` (header limit 72) and husky in Node projects, `hooks/install.sh` from this repo elsewhere, wired into the project's setup command. Never use `--no-verify`; if the hook rejects a message, fix the message.
- Parallel agents: one worktree per task; merge one at a time. Before the first commit, check which branch you are on and fetch `main`.

## Decisions

- Every project keeps `docs/decisions.md` (`templates/decisions.md`): one row per decision with a D-number, the decision, the reason, and what was chosen against.
- Record a decision when the owner settles a design fork or when an agent chooses between real alternatives. Never rewrite an old row; a reversal is a new row that names the one it replaces.
- No time logs in new work. A project that already keeps them may keep its own rule.

## Communication

- Lead with the answer, then the evidence.
- Say what was done and what was not: not done, not verified, skipped, and why.
- When you rely on something the owner said earlier, quote their words with the date.
- Ask only what the owner must decide. Look up everything else.
- Do not claim what you have not checked. "Should work" means run it.
