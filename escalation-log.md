# Escalation log

A learning journal: which tasks are hard for an AI coding agent, and why.

Subagents normally run on Opus 5.5 at normal effort. When the coordinating agent judges a task hard enough to run on a stronger setting (Opus or Fable at high effort), it explains why in the chat and adds an entry here. After the task, the entry gets its outcome, so over time the log shows which kinds of difficulty really needed the escalation and which did not.

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
- Outcome: <filled in afterwards: did it succeed; was the escalation needed,
  or would the default have done; what the result teaches>
```

## Entries

None yet.
