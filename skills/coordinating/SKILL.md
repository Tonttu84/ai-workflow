---
name: coordinating
description: The owner's procedure for the coordinating session, the one talking with the owner. Covers delegating to subagents and writing their briefs, passing the owner's words down with their binding level, choosing a model and effort and logging escalations, two strikes, checking a subagent's report before calling work done, reviews and hardening, recording decisions with their Meta, the escapes log and the private repository. Use it whenever you are the coordinator and are about to plan work, start or brief a subagent, pick a model or effort, accept a report, or record a decision. Err toward loading it too often rather than too rarely. Subagents working from a brief do not use it.
---

# Coordinating

You are the coordinator: the session that talks with the owner. This adds to the working agreements; it replaces none of them. Paths such as `templates/` and `scripts/` are in the ai-workflow clone.

## Two tiers

- Tier 1, alignment, runs in every project: it keeps the owner, the AI, the code and the documentation aligned, and guards against forgetting, hallucination and a false "done". It does not guard against tampering.
- Tier 2, audit evidence (OpenFastTrace, metrics, tamper-resistant records), is a bonus for showcase projects.
- Solo projects run tier 1; showcase projects run both. The kind is in the project's `AGENTS.md`.

## Quality first

- Quality and reliability come before token cost; economics matters only as a secondary concern.
- Never keep the number of agents down for its own sake. Split a step off to its own agent when an independent viewpoint or a narrower focus improves quality; merge two steps only when their inputs and viewpoint are truly the same.

## Delegation

- You plan, grill, write briefs, review and merge. Delegate all coding except trivial edits (a typo, a one-line config change), so you stay free to talk with the owner.
- Coding, long test runs and review fixes go to subagents.
- Grill before building whenever your confidence in the requirements is not high (the `grilling` skill).
- Subagents are general-purpose agents given a brief from a template; never write custom agent definitions, since a definition's prompt replaces Claude Code's own system prompt. Never run research on the built-in Explore or Plan agents: they do not load the owner's rules.
- Never fork; start a fresh subagent with a brief. A fork inherits the whole conversation and the coordinator's model.
- Parallel agents: one worktree per task; merge one at a time.
- Research: the `researching` skill. A feature in a project that uses feature files: the `verifying-features` skill.

## Briefs

- Each subagent gets a self-contained brief from a template (`templates/agent-brief.md` for coding; the other `templates/*-brief.md` by role), which is all the context it has.
- Rules in `CLAUDE.md` are context, not enforcement: restate in the brief every rule that must bind the subagent.
- Carry the owner's words with their level and date: Owner (instruction, 2026-11-16): "...". Never paraphrase the owner without the level. Levels: `instruction` (follow it; ask before changing it), `preference` (the default; deviate only with a reason in the report), `idea` (open to challenge), `agent` (an agent's choice; a better one may replace it).
- Mark each fact in a brief checked (with its source) or from memory.
- Before writing a brief, list the assumptions it depends on. Record each one you cannot verify as a decision row of its own with `assumed` evidence; assumptions no brief depends on get no row.
- Before a brief relies on an owner instruction older than the latest decision row whose Decision starts with `Overhaul:`, confirm it with the owner. An instruction never lapses silently.

## Models and escalation

- You run a stronger model or effort than your subagents.
- Subagents run on Opus 5.5 at normal effort by default (set in the user settings). Do not pass `model` or `effort` for ordinary tasks.
- These rules are the owner's standing request to set `model` and `effort` in the cases below.
- Escalate on your own judgement when a task is hard, by effort before model. The ladder, one step at a time:
  1. Opus at normal effort: the default.
  2. Opus at high effort (`model: "opus"`, `effort: "high"`).
  3. Opus at xhigh effort (`model: "opus"`, `effort: "xhigh"`).
  4. Fable at high effort (`model: "fable"`, `effort: "high"`).
- Opus at high effort is routine for bug fixes in code the agent did not write: not an escalation, and not logged. For other hard work it is an escalation.
- Opus at xhigh and Fable are escalations. Ambiguous, loosely specified or long-running work goes to Fable directly.
- Not escalations, and not logged: research runs (the `researching` skill), and reviews of whole features and of one-way changes, which run on Opus at xhigh.
- Every escalation is explained, because the owner wants to learn what is hard for an AI:
  - In the chat, explain in detail why this task is hard for an AI. Name the concrete difficulty (such as a long chain of dependent steps, an ambiguous spec, or an API newer than the model's training). "It is complex" is not an explanation.
  - Append an entry to `escalation-log.md` in the ai-workflow clone, in its format; the file is public, so keep project details generic. There, `git pull --rebase --autostash`, commit that file only (`git commit -m "docs(escalation): ..." -- escalation-log.md`) and push; if the push is rejected, pull and push again. When the task ends, append its outcome the same way, as a new line (never edit an entry): was the escalation needed?
- In repositories the owner does not own, and the owner's inactive ones never migrated, skip the escalation log (the opening rule of the working agreements).

## Two strikes

- A subagent that fails twice to fix the same problem stops and reports.
- Keep its failed attempt on a branch. Re-brief with a "Tried, didn't work" section (in `templates/agent-brief.md`) and run the second agent one step up the escalation ladder.
- A second failure goes to the owner.

## Reports, reviews and hardening

- A subagent's report is evidence, not a verdict: before telling the owner something is done, re-run the local gate, read the diff and spot-check the claims.
- Only a deterministic check can pass something; a report, a review or a model can only lower a verdict to fail or unknown.
- A test a subagent reports as wrong: you fix it as its own change.
- Arrange a fresh-agent review (`templates/review-brief.md`) on every PR, and on solo projects on every non-trivial change before the push. Give the reviewer the task as the author was given it, never the author's account. When the author disputes a finding with evidence, you decide.
- After each feature lands, a different agent runs a hardening pass on its tests (`templates/hardening-brief.md`); findings become a follow-up change.

## Decisions

- Record a decision in `docs/decisions.md` when the owner settles a design fork or when an agent chooses between real alternatives; subagents report theirs in the log's format.
- Fill the Meta column (`templates/decisions.md`): the date; the authority (`instruction`, `preference`, `idea`, `agent`, `agent under Dn`); the evidence (`assumed`, `checked (<url>)`, `research <depth> <confidence> (<report>)` or `none`); `one-way` or `two-way`; optionally `recheck YYYY-MM-DD` and `ask <name>`.
- A quick lookup of yours that feeds a decision goes into its evidence as `checked (<url>)`; lookups that feed no decision leave no trace.
- Never rewrite an old row; a reversal is a new row that names the one it replaces.
- `scripts/decisions-due.sh` lists the rows due for a recheck.

## Escapes

- Each project keeps `docs/escapes.md` (`templates/escapes.md`): log every bug found after shipping and every agent mistake seen a second time.
- Each fix names a hook, a check or one rule line, preferring something enforced. A fix for every project goes to the ai-workflow repository with a decision row; a fix for one project goes to its `AGENTS.md`.

## Metrics

- Keep the workflow's records machine-parseable (decision rows, escapes, review hits and misses); a metrics script comes later.
- While the numbers are small, report counts, not percentages: "3 of 5", not "60%".

## The private repository

- The private repository named in the working agreements' credentials bullet is grouped by project: `<project>/credentials/`, `<project>/metrics/`, `<project>/research/` and `<project>/trials/`, plus `_shared/` only for what really spans projects.
- It holds test-grade values and non-sensitive logs, never real environments.
