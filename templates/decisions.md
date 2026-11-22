# Decisions

One row per decision. Never rewrite an old row: a reversal is a new row that names the one it replaces.

Meta holds fixed keywords in this order, separated by ` · `:

- Date: `YYYY-MM-DD`, always first.
- Authority: the owner's `instruction` (follow it; ask before changing it), `preference` (the default; deviate only with a stated reason) or `idea` (open to challenge); `agent` (an agent's own choice); `agent under Dn` (an agent's choice within the owner's decision Dn).
- Evidence: `assumed` (not verified), `checked (<url>)` (a quick lookup by the coordinator), `research <normal|deep> <HIGH|MEDIUM|LOW> (<path to the report>)` (casual research leaves no report: it is `checked`) or `none`.
- Reversibility: `one-way` or `two-way`.
- Optional `recheck YYYY-MM-DD`, for facts that go stale (prices, API versions, limits). The ai-workflow script `scripts/decisions-due.sh` lists the rows that are due. A later row clears a recheck when its Decision cell names the ID and the row has a recheck of its own, or says `Rechecked <ID>` (for example "Rechecked D5: still holds").
- Optional `ask <name>`: who to ask about it, only in projects with more than one person.

Rules:

- Rows written before the Meta column leave it blank.
- An unverified assumption gets its own row only when a brief depends on it.
- A decision that starts with `Overhaul:` marks a major rework. Before a brief relies on an owner instruction older than the latest `Overhaul:` row, confirm it with the owner.

<!-- D2 (an owner instruction backed by research) and D3 (an assumption) show the format; replace them. -->

| ID | Decision | Reason | Chosen against | Meta |
| --- | --- | --- | --- | --- |
| D1 | <what was decided> | <why> | <the alternatives, and why not> | <YYYY-MM-DD> · <authority> · <evidence> · <one-way or two-way> |
| D2 | <the owner's instruction, e.g. Payments use the provider's hosted checkout.> | Owner: "<their words>". | <the alternatives, and why not> | 2026-11-16 · instruction · research normal HIGH (docs/research/payments.md) · one-way · recheck 2027-05-16 |
| D3 | <an assumption, e.g. Assumed: the provider allows 100 requests a minute.> | <the brief that depends on it>; <why it could not be checked>. | — | 2026-11-16 · agent · assumed · two-way |
