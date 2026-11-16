# Research brief: <the question, in a few words>

<!-- For a research subagent. Depth normal: one agent. Depth deep: several
     agents or a deep-research skill, on the most capable model; they still
     follow this brief, its rules and its output path. Casual research (a
     quick lookup) needs no brief: the coordinator does it itself.
     Never run research on the built-in Explore or Plan agents: they do
     not load the owner's rules. -->

## The question

- Question: <one question>.
- The decision it feeds: <Dn, or the decision still to be made>.
- Depth: normal | deep  <!-- keep one -->

## What is known

<The facts so far, each marked `(checked: <source>)` or `(memory)`, and the options on the table. State them neutrally: never the coordinator's preferred answer, since an agent handed a hypothesis tends to confirm it.>

## Budget

About <n> searches and <n> sources. When the budget runs out, stop and report what you found. More research is a new brief, not a longer one.

## Sources, in this order

1. Official documentation and source code.
2. Existing tools that already solve the problem (prior art).
3. Established software-engineering practice.
4. Data and studies.
5. Practitioner posts last; say whether the author sells a related product.

## Rules

- Every factual claim cites a URL. For an API or a library, give its version and the page's date.
- Mark each finding by its source: HIGH (official docs, source code), MEDIUM (established references, studies), LOW (community posts, forums, vendor blogs).
- A critical claim needs two independent sources.
- Keep facts apart from inference. Give the options with their trade-offs; mark any recommendation as inference.
- Say plainly what you could not find or fetch. Never fill a gap from memory without marking it `(memory)`.
- When a fact question turns into a question of the owner's preference (A is faster, B is cheaper), list it under "Questions for the owner" instead of choosing.
- At most two research rounds. A fact still open after two goes to the owner as "unknown"; the coordinator records it as an `assumed` decision row.
- Change no file but the report. Commit it alone on <branch> as `docs(research): <topic>`; the commit hook must pass.

## Output

Save the report as `docs/research/<topic>.md`, answer first, at most about 1,000 words at normal depth (<n> at deep):

```text
# Research: <topic>

Date: YYYY-MM-DD · Depth: normal | deep
Question: <the question>
Feeds: <Dn or the decision>

## Answer
<Two to five sentences. Facts only; inference marked as such.>

## Findings
1. <claim> [HIGH] <URL> (<version>, <date>)

## Options
<Each option with its trade-offs.>

## Not found
<What could not be found or fetched.>

## Questions for the owner
<Preference questions, or "none".>
```

<!-- For the coordinator: spot-check the key claims before relying on
     them, then record the decision in docs/decisions.md with a link to
     the report in its Meta (research <depth> <confidence> (<path>)). -->
