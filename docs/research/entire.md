# Research: Entire as evidence for verifying AI-agent work

Date: 2026-11-16 · Depth: normal (round 2 of 2)
Volatility: fast
Question: What does Entire record and guarantee, under what privacy model, and can its records serve as deterministic evidence for verification steps in a solo developer's AI-agent workflow?
Feeds: adopting Entire, and for which steps (D93)

## Answer
Entire records a redacted copy of each agent transcript in plain git objects under `refs/entire/checkpoints/<shard>/<id>`, linked to a commit by an `Entire-Checkpoint` trailer. By default it pushes those records with the code, so on a public repo the transcripts are public. The records are not tamper-evident. Content signing is best-effort with the user's own key and fails open. The stored SHA-256 sits in the same tree it describes, and checkpoints can be backfilled, rewritten or deleted. The only signed, append-only ledger (gittuf RSL) exists only for repositories hosted on Entire. Entire extracts only *modified* files. Which files an agent read can be found only by parsing the raw transcript, and foreground read-only subagents leave no record at all. Inference: Entire is useful as an audit trail, but it cannot pass a black-box check, a no-diff check or a walkthrough sign-off on its own.

## Findings
1. A checkpoint holds `metadata.json` plus one directory per session with `full.jsonl` (raw transcript), `transcript.jsonl`, `prompt.txt` and `content_hash.txt`. Subagents go under `tasks/<tool_use_id>/` (`task.json` and `agent-<id>.jsonl`). [HIGH] https://github.com/entireio/cli/blob/main/api/checkpoint/metadata.go (main at v0.13.4, 2026-11-13)
2. The storage is ordinary git, readable without Entire. Since 0.10.0 each checkpoint has its own ref; before that, all checkpoints lived on the branch `entire/checkpoints/v1`. [HIGH] https://docs.entire.com/guides/checkpoints/checkpoint-storage.md (undated, checked against 0.10.2); `refs_naming.go` in the source.
3. Tamper evidence: `content_hash.txt` is `sha256` of the transcript, stored beside it in the same tree (persistent.go:1094). Signing uses the user's GPG/SSH key only when `commit.gpgsign` is on, and "Signing does not block a commit". Backfill, OPF rewrite and `entire checkpoint delete` all change stored checkpoints. [HIGH] https://docs.entire.com/security.md; `cmd/entire/cli/checkpoint/objectsigner.go`
4. The signed, append-only gittuf RSL records pushes of checkpoint refs only for "repositories hosted on Entire". The server writes the entries. A script can check `entire rsl verify --fetch --json` (exit 0 = verified). [HIGH] https://docs.entire.com/guides/repositories/reference-state-log.md; https://github.com/entireio/entire-rsl (MIT)
5. Claude Code hooks installed: SessionStart, SessionEnd, Stop, UserPromptSubmit, SubagentStart, SubagentStop and PreToolUse/PostToolUse on Agent and Skill. Subagent work is stored inside the parent session's checkpoint. [HIGH] `cmd/entire/cli/agent/claudecode/hooks.go`; https://docs.entire.com/agents/claude-code.md
6. A foreground read-only subagent "leaves no record". Background ones are kept. [HIGH, docs only; the source docs do not contradict it] https://docs.entire.com/agents/claude-code.md. Subagent capture is new: committed checkpoints held no subagent data until 0.10.3 (2026-08-27), and Claude Code background subagents first reached checkpoints in 0.11.4 (2026-10-06). [HIGH] https://github.com/entireio/cli/blob/main/CHANGELOG.md
7. File data comes from Write/Edit tool calls plus `git status`. There is no "files read" field. A read shows up only as a tool call in the stored raw transcript. [HIGH] `docs/architecture/claude-hooks-integration.md`; metadata.go (`files_touched`, task `files`)
8. Linking to commits: the trailer sits inside the commit object, and the checkpoint stores `commit_sha`/`linked_commits`. A script can resolve trailer → ref → metadata. The checkpoint content is not covered by the commit hash. [HIGH] `cmd/entire/cli/trailers/trailers.go`; metadata.go
9. Git hooks installed: prepare-commit-msg (writes the trailer), commit-msg, post-commit, post-rewrite, pre-push. Existing hooks are renamed `*.pre-entire` and chained, with Entire's hook running first. Entire installs into whatever `git rev-parse --git-path hooks` resolves to, which honours `core.hooksPath`. [HIGH] `cmd/entire/cli/strategy/hooks.go`; https://docs.entire.com/guides/configuration/git-hooks.md
10. Trails review agents are LLM jobs (harness `claude`/`codex`/`pi`, a chosen model) that output a score or verdict, a rationale and findings. Gates apply fixed rules (up to date, approval count, findings severity threshold, CI checks) to that evidence. Custom agents need a payment method. [HIGH] https://docs.entire.com/guides/trails/agents.md; https://docs.entire.com/guides/trails/gates.md
11. Privacy:
    - Pushing checkpoints (`push_sessions`) is on by default, and the docs say "If your repository is public, so are they".
    - `entire checkpoint explain --generate` sends a redacted transcript to the summary provider.
    - Telemetry goes to PostHog EU and does not include prompts or code.
    - Redaction has 8 regex and entropy layers that "does not certify a checkpoint as safe to publish". Images are not redacted, and low-entropy passwords on a command line pass through (issue #2898, open).

    [HIGH] https://docs.entire.com/security.md; https://docs.entire.com/guides/configuration/privacy-and-redaction.md. The home page says "Sensitive data never leaves your machine" [LOW] https://entire.com, which the docs contradict.
12. Brain stores memory locally. It syncs only after `entire brain connect`, its extraction can send context to a model provider, and `ENTIRE_BRAIN_NO_EGRESS=1` blocks that traffic. [HIGH] https://docs.entire.com/guides/brain/storage-and-sync.md
13. Pricing: "Entire bills only for Agent usage", and other features are free. Trial credits are paused. [HIGH] https://docs.entire.com/billing.md (prices as of 2026-11-13). Login is needed for cross-repo search, mirrors, the web UI and cloud dispatches. [HIGH] https://docs.entire.com/platforms/cli-and-entire-com.md. The CLI, Brain, graph and rsl are MIT (GitHub org listing).
14. Maturity:
    - Releases come every few days; 0.13.2 to 0.13.4 shipped 10–13 Nov.
    - There are 440 open issues, 28 of them labelled bug. Examples: #2111, a commit that recorded an empty tree; #784, later commits silently missing the trailer; #2215, SubagentStop dropped; #1349, a pre-push conflict with lefthook.
    - Windows fixes: a `git commit -m` hang (0.11.5), ref pushes failing past about 340 refs (0.13.1), and the PATH lookup (0.13.3).

    [HIGH] GitHub releases, issues and CHANGELOG
15. An independent hands-on review (Ritza/Tech Stackups, no affiliation disclosed) found a full API key on an unredacted shadow branch and passwords typed into prompts stored verbatim. [LOW] https://techstackups.com/guides/entire-io-hands-on-what-it-actually-captures/ (2026-05-19)
16. Comparable tools: git-ai stores AI line attribution in git notes, and Agent Trace (Cursor, RFC v0.1.0) is a format for attribution records. Neither records sessions in a tamper-evident way. [LOW/MEDIUM] https://github.com/cursor/agent-trace; https://usegitai.com/track-ai-code

## Options
- **Do not adopt.** Use Claude Code's own deny rules or a PreToolUse hook to block source and diff reads (memory: such deny rules exist; issue #2260 shows Entire uses one). Bind the walkthrough with a signed tag or note on the commit (memory). This is deterministic, but it leaves no session history.
- **Private solo repos, local only (`push_sessions: false`).** You get an audit trail and a script check that every agent commit carries a trailer. Gaps: it does not prove reads, it is not tamper-evident, and hook bugs can drop links.
- **Private repos, pushed to a separate `--checkpoint-remote` repo.** You keep the history off-machine. The risk is redaction gaps.
- **Public showcase.** Push to a private checkpoint remote, never to the public repo. Inference: anything else publishes the transcripts.
- **Per verification step** (inference):
  - Black-box tester and trace agent: Entire can only *lower* a verdict, by a transcript scan that finds a forbidden read. It cannot *pass* one, because a missing record is not proof.
  - Walkthrough: no local sign-off exists. Trails approvals and the RSL need hosting on Entire.
  - Trails agents: LLM judgement, so under the owner's rule they can only block, never pass.
- **Hook interplay** (inference from the source plus `hooks/install.sh`): Entire would rewrite the committed `.githooks/` directory, renaming `commit-msg` and adding three new hooks. The owner's commit-msg hook checks only the subject and line 2, so the trailer should pass it. I have not run this.

## Not found
- Behaviour after 0.10.2: the docs are checked only against that version, while 0.13.4 is current.
- Whether a foreground read-only subagent really leaves no record (the source docs neither confirm nor deny it).
- What dispatch sends, and what `--local` does.
- What data Trails sends to model providers.
- Whether the trailer survives a GitHub squash merge.

The security page carries a "Documentation Index" note addressed to AI agents ("Fetch the complete documentation index…"). It was harmless, and I did not act on it.

## Questions for the owner
1. Should checkpoints from public showcase repos go to a private checkpoint remote, or stay local?
2. Is an audit trail that can only lower a verdict worth adding a hook chain and an extra dependency that changes every few days?
3. Should the black-box and no-diff rules be enforced with Claude Code deny rules instead, keeping Entire only as a record?

## Spot-checked by the coordinator

On 2026-11-18, while preparing the trial (D134, D135). The source was read directly. The docs were read through a fetch agent.

- 0.13.4 is the current release (finding 1): held. Checked against https://github.com/entireio/cli/releases/tag/v0.13.4, where the Windows amd64 archive is 24.1 MB.
- Entire installs its git hooks into the directory `git rev-parse --git-path hooks` names, which follows `core.hooksPath`, and keeps existing hooks as `<hook>.pre-entire`, run after its own (finding 9): held. Checked against `cmd/entire/cli/strategy/hooks.go` at v0.13.4. The docs page https://docs.entire.com/guides/configuration/git-hooks.md does not mention `core.hooksPath`. Its pre-push hook saves git's ref list and passes it on stdin to the hook it chains to.
- With the committed `.githooks/`, Entire would rename `commit-msg` and add three hooks (Options, hook interplay): did not hold in full. It renames `pre-push` too, and adds `prepare-commit-msg`, `post-commit` and `post-rewrite`. Checked against `gitHookNames` in the same file.
- The Claude Code hooks (finding 5): held in the main, with three differences in v0.13.4. It also installs StopFailure. PreToolUse matches Agent only, while PostToolUse matches Agent and Skill. SubagentStart matches only agents a Workflow launches. Checked against `cmd/entire/cli/agent/claudecode/hooks.go` at v0.13.4.
- Pushing checkpoints is on by default, and `--skip-push-sessions` turns it off (finding 11, Options): held. The setting is `strategy_options.push_sessions`. `entire configure --local --skip-push-sessions` writes it to the gitignored `.entire/settings.local.json`, and `--project` writes it to the committed `.entire/settings.json`. Checked against https://docs.entire.com/cli-reference/configure.md and https://docs.entire.com/guides/checkpoints/keep-checkpoints-local.md.
- Local recording needs no login (finding 13): held. Checked against https://docs.entire.com/cli-reference/login.md and the README of https://github.com/entireio/cli.
