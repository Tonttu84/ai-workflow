# ai-workflow

The working rules I use for every project I build with Claude Code and other AI coding tools: how work is planned, delegated to agents, tested, reviewed and committed. One rules file is loaded into every session; each project adds only what is specific to it.

These rules are how I keep AI-assisted work honest: decisions are written down, tests come first, every change is reviewed by an agent that did not write it, and commit messages are checked by a hook rather than by good intentions.

## How it is used

```text
~/.claude/CLAUDE.md                      one line: @<clone>/rules/working-agreements.md
└── rules/working-agreements.md          shared rules, loaded in every session

<project>/CLAUDE.md                      one line: @AGENTS.md
└── <project>/AGENTS.md                  project specifics: its kind (solo or showcase),
                                         stack, commands, domain rules, quirks
```

- `rules/working-agreements.md` is the only file loaded into every session, so it is kept short: it costs context each time.
- A project's `AGENTS.md` holds only what is specific to that project and says which kind it is. Solo projects commit to `main` once the gate is green; showcase projects go through a pull request, a fresh-agent review and a squash-merge. `AGENTS.md` is the open format other coding tools read; its `CLAUDE.md` is the single line `@AGENTS.md`.
- Everything else here (templates, briefs, the hook, the skills) is used on demand.

## Layout

```text
rules/working-agreements.md   the shared rules, imported into every session
templates/
  AGENTS.md                   a project rulebook skeleton
  CLAUDE.md                   the one line @AGENTS.md
  kickoff.md                  the plan written before any code
  decisions.md                the decision log (D1, D2, ...)
  agent-brief.md              the brief for a coding subagent
  review-brief.md             the brief for a cold reviewer
  hardening-brief.md          the brief for the test hardening run after a feature
  commitlint.config.mjs       commitlint rules matching the hook, for Node projects
  commit-check.yml            CI gate: every commit message and PR title
  dependabot.yml              grouped dependency updates every two weeks
hooks/
  commit-msg                  portable bash hook enforcing the commit rules
  install.sh                  installs the hook into a project
skills/                       the grill skills, tracked from upstream (see skills/README.md)
scripts/
  sync-skills.sh              fetches the latest upstream skills, re-applies local overlays
  apply-skill-overlay.sh      applies one overlay (used by sync-skills.sh)
  install-skills.sh           copies the skills to ~/.claude/skills
tests/                        shell tests for the hook and the scripts (./tests/run.sh)
escalation-log.md             why some tasks needed a stronger model: a learning journal
docs/decisions.md             the decisions behind this repo
```

## Install on a new machine

### 1. Clone

```bash
git clone https://github.com/Tonttu84/ai-workflow.git
cd ai-workflow
make setup        # this repo's own commit hook: git config core.hooksPath hooks
make test         # or ./tests/run.sh
```

### 2. Import the rules in every session

Add one line to the user-level `~/.claude/CLAUDE.md` (on Windows, `%USERPROFILE%\.claude\CLAUDE.md`), pointing at the clone:

```text
@~/code/ai-workflow/rules/working-agreements.md
```

On Windows with the clone on another drive, use an absolute path with forward slashes, for example `@D:/code/ai-workflow/rules/working-agreements.md`.

What the Claude Code memory docs say about `@` imports ([code.claude.com/docs/en/memory](https://code.claude.com/docs/en/memory), checked 2026-11-10):

- Relative and absolute paths both work. A relative path resolves from the file that contains the import (here `~/.claude/`), not from the working directory. `@~/...` paths in the home directory work.
- A path with spaces needs a backslash before each space; a quoted path is not imported at all.
- Imports inside code spans and fenced code blocks are ignored, so mentioning `@AGENTS.md` in backticks is safe.
- Imported files can import further files, up to four hops deep.
- Imported files load in full at the start of every session, together with the file that imports them. An import organises the rules; it does not reduce their context cost.
- Imports in user-scope files such as `~/.claude/CLAUDE.md` load without the approval dialog that project-level imports of outside files get. The exception is Cowork sessions, which skip user-scope imports that point outside the session's working directory.
- Subagents load `~/.claude/CLAUDE.md` too, so they get the same rules, except the built-in Explore and Plan agents and any agent defined with `omitClaudeMd`.

The docs do not show a Windows drive-letter example. To confirm the import works, start a new session and run `/memory`: the rules file should be listed.

### 3. User settings

In the user-level `~/.claude/settings.json`:

- Set the environment variable `CLAUDE_CODE_SUBAGENT_MODEL` to `claude-opus-5-5` (under the `env` key). Subagents then default to Opus 5.5. It is only a default: a model the coordinator passes for an escalation still wins, so do not also set `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`.
- Add `Agent(fork)` to `permissions.deny`. A fork inherits the whole conversation and runs on the coordinator's model; the rules want fresh subagents with a written brief.
- Do not pin a session `model` (D9). The coordinator runs on Fable 5.1 (D5): pick it when starting the coordinating session, for example with `/model`.

Passing `effort` on a subagent call needs Claude Code v2.1.292 or later.

### 4. Skills

```bash
./scripts/install-skills.sh      # copies skills/* to ~/.claude/skills (or $CLAUDE_CONFIG_DIR/skills)
```

Remove any per-project copies of `grilling` and `grill-me` (under a project's `.claude/skills/`) so the user-level copy is the one in use.

### 5. The commit hook in each project

Projects without Node:

```bash
/path/to/ai-workflow/hooks/install.sh /path/to/project            # .githooks/ + core.hooksPath
/path/to/ai-workflow/hooks/install.sh --git-hooks /path/to/project  # or copy into .git/hooks
```

The default mode copies the hook to the project's `.githooks/` (commit it) and sets `core.hooksPath`. Each fresh clone still needs `git config core.hooksPath .githooks` once, so put that line in the project's setup command.

Setting `core.hooksPath` makes git ignore every hook in `.git/hooks`, so the default mode refuses when that folder already holds hooks (pre-commit, husky, lefthook, Git LFS): use `--git-hooks`, move them into `.githooks/`, or pass `--force` to switch them off. It warns when it overrides a global `core.hooksPath`. `--git-hooks` refuses to replace a different `commit-msg` without `--force`.

Node projects may use [commitlint](https://commitlint.js.org) and husky instead, with [`templates/commitlint.config.mjs`](templates/commitlint.config.mjs). It extends `@commitlint/config-conventional` so that it accepts and rejects the same messages as the hook; its header lists the few differences.

The hook checks: a subject of the form `type(scope)!: summary` with an allowed type (`feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore`, `revert`), a lower-case scope, at most 72 characters, no trailing period, and a blank line before the body. Subjects that start the way git's own merge, revert, reapply, `fixup!`, `squash!` and `amend!` messages do pass unchecked, whether git wrote them or a person typed them; `templates/commit-check.yml` keeps `fixup!`, `squash!` and `amend!` commits off `main`. Comment lines count unless git drops them (it does in its editor, not with `-m` or `-F`), and the length is counted in characters. It does not check body wrapping, so long URLs and logs can go in a body.

### 6. CI: the gate for commit messages

The hook is feedback while writing, not a gate: `core.hooksPath` is local config that a clone does not copy, `--no-verify` and GitHub's web editor skip it, and a squash merge writes its commit on GitHub. Three layers:

1. The hook catches a bad message as it is written.
2. CI checks every commit that reaches `main` and every PR title: copy [`templates/commit-check.yml`](templates/commit-check.yml) to the project's `.github/workflows/`. This is the gate.
3. A ruleset on `main` that requires the `commit-check` jobs and blocks force pushes makes the gate binding. On GitHub Free, rulesets work only on public repositories; a private repository is a recorded exception (the check is visible but does not block) until the plan changes.

A squash merge turns the PR title into the commit subject on `main`. By default GitHub does that only for pull requests with more than one commit; a one-commit PR gets that commit's subject. Make the PR title the subject in every case, once per repository:

```bash
gh api -X PATCH repos/OWNER/REPO \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY
```

The workflow runs the project's committed `.githooks/commit-msg`, as it was before the change, on every commit of a pull request (base to head) and of a push to `main` (before to after; for a new branch only the head), so a change cannot weaken its own check. Merge commits git writes pass; `fixup!`, `squash!` and `amend!` commits fail. It also checks the PR title and rejects titles the hook would let through as git's own messages (`Merge ...`, `Revert "..."`, `fixup! ...`). Actions are pinned by SHA, the token is read-only and not persisted, and the title reaches the script through an environment variable, never pasted into it.

## Starting a new project

1. Grill the plan, then copy `templates/kickoff.md` to `docs/kickoff.md` and fill it in before writing code.
2. Copy `templates/AGENTS.md`, `templates/CLAUDE.md` and `templates/decisions.md` (as `docs/decisions.md`).
3. Install the commit hook, add `templates/commit-check.yml` and `templates/dependabot.yml`, protect `main`, and set the squash setting if pull requests are squash-merged (step 6 above).

## Moving an existing project to these rules

1. Add `AGENTS.md` (stating the kind), the one-line `CLAUDE.md` and `docs/decisions.md` from `templates/`.
2. Install the commit hook with `hooks/install.sh` and add its `git config` line to the setup command: a fresh clone has the hook off until that runs.
3. Smoke-check it in that repository: a bad message is rejected (`git commit --allow-empty -m "bad"`), a good one passes, and the project's existing hooks (pre-commit, Git LFS, husky) still run.
4. Once the hook is committed and on `main`, add `templates/commit-check.yml` (a change that adds both is checked with its own copy of the hook, with a warning) and protect `main` with a ruleset (step 6 above); if pull requests are squash-merged, set `squash_merge_commit_title=PR_TITLE`. The first pull request should show the commit check running and passing.
5. Turn on Dependabot from the template: copy `templates/dependabot.yml` to `.github/dependabot.yml`, uncomment the project's ecosystems, and enable Dependabot security updates in the repository settings. A repository with nothing to update skips this.

## Updating

- Rules: edit in this repo, commit under its own hook, push, and `git pull` on other machines. A new session picks up the change.
- Skills: `./scripts/sync-skills.sh`, review `git diff skills/`, run the tests, commit, then `./scripts/install-skills.sh`. See [`skills/README.md`](skills/README.md).
- Escalations: the coordinating agent appends entries to `escalation-log.md`, commits that file alone and pushes it.

## Tests

`make test` (or `./tests/run.sh`) runs the shell tests: a table of good and bad commit messages for the hook plus real `git commit` runs through it, both install modes end to end, the skill sync, overlay and install scripts against a local fake upstream, and the templates that must match the hook. `make lint` runs [ShellCheck](https://www.shellcheck.net), which must be installed. CI runs both on pushes to `main` and on pull requests.

## Licence

MIT, see [`LICENSE`](LICENSE). The grill skills in `skills/` are by Matt Pocock ([mattpocock/skills](https://github.com/mattpocock/skills)) and stay under their own MIT licence in [`skills/LICENSE`](skills/LICENSE).
