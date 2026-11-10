# Escalation log

A learning journal: which tasks are hard for an AI coding agent, and why.

Subagents normally run on Opus 5.5 at normal effort. When the coordinating agent judges a task hard enough to run on a stronger setting (Opus or Fable at high effort), it explains why in the chat and adds an entry here. After the task, an outcome line is added, so over time the log shows which kinds of difficulty really needed the escalation and which did not.

## Entry format

Newest entry at the bottom. Keep project details at the level a stranger may read: this file is public.

```markdown
### YYYY-MM-DD: <project>, <task kind>

- Model and effort: <opus | fable>, high
- Task: <one sentence on what was asked>
- Why it is hard for an AI: <the concrete difficulty, in a few sentences:
  long chains of dependent steps, an ambiguous spec, concurrency, numeric
  precision, an API newer than the model's training, too much code to hold
  at once, ...>
```

When the task ends, append its outcome as a new line at the bottom of the file. Never edit an entry: sessions in several projects write here at once, and the file merges by keeping both sides (`merge=union`), so an edited line would survive next to its old copy. An older entry's `Outcome:` placeholder stays as it is.

```markdown
- Outcome (YYYY-MM-DD: <entry title>): <did it succeed; was the escalation
  needed, or would the default have done; what the result teaches>
```

## Entries

### 2026-11-10: Lease Loop, responsive layout fixes against a browser layout spec

- Model and effort: opus, high
- Task: make a Playwright layout spec that checks 19 pages × 6 languages × 15 viewports pass (739 findings from about a dozen root causes), and add a wide-screen layout for list pages.
- Why it is hard for an AI: the agent cannot see the pages, only the spec's
  findings, so each fix is a guess about CSS it then has to confirm with a
  four-minute browser run; that is a long loop of dependent edit, run,
  read-the-findings steps. One CSS change (a global `overflow-wrap`, a
  `min-w-0` on a grid) fixes findings on many pages and can create new ones
  on others, so it has to hold many components and their interactions at
  once. And a fix must keep the design intact (no text broken mid-word where
  it reads badly, no squashed layouts), which no check asserts: the agent
  needs judgement about what a page should look like, not only what passes.
- Outcome: <to fill in>
