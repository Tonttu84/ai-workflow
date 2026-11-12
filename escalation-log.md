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
- Outcome (2026-11-10: Lease Loop, responsive layout fixes against a browser layout spec):
  succeeded after three review rounds; the spec went from 889 findings (not
  739: the first log miscounted) to 0 on every page, size, language and text
  size. The escalation was needed: the agent ran about 20 four-to-ten-minute
  browser runs, and each fresh reviewer still found what the checks could not
  see (overlapping boxes, mid-word breaks, transformed boxes, a lone arrow at
  320 px), so the hard part was making the checks see enough, not making the
  page pass them. Lesson: a layout spec is only as good as its blind spots;
  plant faults to prove every new check both ways, and look at screenshots.

### 2026-11-12: smartHeating, acknowledging device writes in a control loop

- Model and effort: opus, high
- Task: make a heating controller count a write to a home-automation entity
  as applied only when the automation server acknowledges it (a reply body,
  then a follow-up state read), with a re-send safety net, measured against
  the real server image first.
- Why it is hard for an AI: the bug lives in the gap between three systems
  (the controller's landing state machine, the server's event model, a vendor
  integration), and the obvious signal (HTTP 200) lies. The fix touches a
  safety-relevant state machine with a history of silent-hold bugs, so every
  change must be traced through a long chain of dependent rules (landing,
  override detection, alerts, retry cadence). The existing test fakes hide the
  very mechanism at fault (a state age that is always zero), so the agent has
  to notice and repair the fake rather than trust a green run. It also has to
  measure the server's behaviour before relying on it, not reason from source.

### 2026-11-12: upstream contribution, a fix in a performance-tuned core state machine

- Model and effort: fable, high
- Task: design, implement, test and benchmark several candidate fixes for a
  stale cached timestamp in a large open-source project's core state object,
  so that the owner can argue one of them to maintainers who already
  rejected a simpler patch on performance grounds.
- Why it is hard for an AI: the acceptance test is a sceptical human, not a
  green suite. The constraints that matter (which paths are hot, what
  "churn" means, why the field was kept off the public API) live in four old
  pull requests and two maintainers' comments, not in the code. The cache is
  a C-level descriptor whose behaviour cannot be read off the Python source,
  so intuitions about cost are wrong until measured. One candidate needs a
  hand-spliced serialisation to be byte-identical to the encoder for
  arbitrary data. The agent must compare five designs honestly, including
  discarding the coordinator's own earlier proposal, in an unfamiliar repo
  whose toolchain is newer than its training, on a machine where timings are
  noisy and a mistake with Docker would touch a live system.
