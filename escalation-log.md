# Escalation log

A learning journal: which tasks are hard for an AI coding agent, and why.

Subagents normally run on Opus 5.5 at normal effort. When the coordinating agent judges a task hard enough to go up the escalation ladder, effort before model (D81: Opus at high effort, then Opus at xhigh, then Fable at high), it explains why in the chat and adds an entry here. Opus at high effort for a bug fix in code the agent did not write is routine and gets no entry; for any other hard work it is an escalation (D97). After the task, an outcome line is added, so over time the log shows which kinds of difficulty really needed the escalation and which did not. Entries written before the ladder record `opus, high` or `fable, high`.

## Entry format

Newest entry at the bottom. Keep project details at the level a stranger may read: this file is public.

```markdown
### YYYY-MM-DD: <project>, <task kind>

- Model and effort: <opus, high | opus, xhigh | fable, high> (step <2 | 3 | 4>
  of the D81 ladder; or `fable, high` directly for ambiguous, loosely
  specified or long-running work)
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
- Outcome (2026-11-13: smartHeating, acknowledging device writes in a control loop):
  succeeded, and the escalation was needed. The agent stopped twice on its
  own measurements before writing the fix: the server's REST view served a
  stale timestamp, and the vendor integration reported two seconds after
  some calls, so the first two agreed rules were both wrong. A cold reviewer
  then found by mutation one untested path per round, three rounds. Lesson:
  for a rule about another system's behaviour, measure first and let the
  agent stop; the design changed more from measurements than from thinking.
- Outcome (2026-11-13: upstream contribution, a fix in a performance-tuned core state machine):
  the prototype succeeded: seven candidates measured, three finished with
  tests that fail without the fix, and the coordinator's re-run on a quiet
  machine reproduced the numbers. The escalation was needed for the
  judgement, not the code: the agent corrected the coordinator's framing in
  four places (what the main cost was, which reply was affected, a wrong
  corner case in the "simple" option, a C descriptor that was not faster
  than plain Python). Whether maintainers accept it is still open; the
  project's AI policy leaves the arguing to the human.

### 2026-11-15: hackathon web app, browser tests red after combining two feature branches

- Model and effort: fable, high
- Task: sort 16 failing browser tests (beside 17 out-of-memory crashes) on a tree that combines two independently built feature branches, fix test or screen for each, and get every browser test green with five-minute runs on a memory-starved laptop.
- Why it is hard for an AI: each failure has three possible causes that look
  alike in the log (a real defect in a screen, a test written for one branch
  that does not know the other branch's redirects, seed and wording, or a
  knock-on from a crashed page or from state an earlier spec left in the
  database), and telling them apart needs the intended product behaviour of
  two branches held at once, which no file states in one place. The
  feedback loop is slow and noisy: a run takes five minutes and the machine
  crashes browsers at random, so a red test is not evidence by itself. And
  the tempting fix is the wrong one: cheaper agents on this project loosened
  guarding tests to go green three times in one night, so the judgement of
  "update the assertion to the new truth" against "the screen is wrong" is
  the whole task. The owner asked for the stronger model by name.
- Outcome: <to fill in>
- Outcome (2026-11-15: hackathon web app, browser tests red after combining two feature branches):
  succeeded in about 45 minutes: 59 of 59 browser tests passed across one
  full run and two targeted ones, ten stale assertions updated with reasons,
  none skipped, and one real screen defect found and fixed test first. The
  escalation was needed: the agent overturned the diagnosis three earlier
  agents and the coordinator had accepted ("the laptop runs out of memory")
  by reproducing the crash on a blank page: a browser API call ended the
  page. It also noticed that the cheaper agent it replaced was still
  running in the same folder and stopped itself instead of fighting it.
  Lesson: "flaky, must be memory" is a guess until someone reproduces it in
  isolation; and verify that a stopped agent is really gone.
