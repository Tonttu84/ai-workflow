---
name: researching
description: When and how the coordinator researches facts before a decision, at casual, normal or deep depth, where research reports live, and when an old report is stale. Use it whenever a decision is costly or one-way, rests on facts that may have changed since your training (tools, versions, prices, models, APIs, services), or enters a new domain, whenever a grilling question needs a fact you have not checked, and before reusing a research report. Err toward using it too often rather than too rarely. Subagents working from a research brief follow the brief instead.
---

# Researching

For the coordinator. A research subagent works from `templates/research-brief.md`, which carries its own rules; the paths here are in the ai-workflow clone unless they name a project.

## When

- Research before design when a decision is costly or one-way, rests on facts that may have changed since the model's training, or enters a new domain.
- Skip it for bug fixes and familiar patterns.
- During grilling, mark the facts in every recommended answer checked or from memory. Check a fact that matters before asking, when a few searches settle it. A bigger one becomes background research, and the question that depends on it waits while the others go on. A decision that rests on memory is recorded as `assumed`.

## Check the library first

- Before new research, look for a report on the question: in the project's `docs/research/`, in the ai-workflow repository's `docs/research/` and, for private work, under `<project>/research/` in the private repository.
- Check staleness when you reuse a report, not on a calendar. By its date and Volatility mark: a `fast` report older than about 6 months, or a `slow` one older than about 12, counts as leads only until it is refreshed; a `stable` one does not date.
- A report becomes history once the decision it fed has been carried out (built, launched, bought). It is not refreshed.

## Depth and model

- Casual: a quick lookup you do yourself, with no brief. When it feeds a decision, record `checked (<url>)` in that decision's Meta evidence; a lookup that feeds no decision leaves no trace.
- Normal: one general-purpose agent on Opus at high effort, briefed from `templates/research-brief.md`.
- Deep: several general-purpose agents on Opus at xhigh effort, one sub-question each, with its own brief and report (`Depth: deep (<n> of <m>)`); you read the reports together. A second round on Fable at high effort runs only if the first fell short.
- These settings are not escalations and are not logged.
- Never on the built-in Explore or Plan agents: they do not load the owner's rules.
- At most two rounds. A fact still open after them goes to the owner as "unknown" and is recorded as an `assumed` decision row.
- A fact question that turns into a question of preference (A is faster, B is cheaper) goes to the owner.

## Where reports live

- General research (tools, practices, models): the ai-workflow repository's `docs/research/`. It is public, so keep it generic: no project names, private paths, accounts or personal details.
- Project-specific research: that project's `docs/research/`.
- Private research: `<project>/research/` in the private repository.

## After a report

- Spot-check the key claims before relying on them, and append the result to the report under "Spot-checked by the coordinator" (the brief's closing comment shows the form), or "Not spot-checked."
- Research agents never commit: commit the report alone as `docs(research): <topic>`.
- Record the decision it fed in `docs/decisions.md`, with `research <depth> <confidence> (<path>)` as its evidence.
