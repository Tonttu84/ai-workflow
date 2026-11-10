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
- Do not pin a session `model`; choose the coordinator's model per session.

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

The hook checks: a subject of the form `type(scope)!: summary` with an allowed type (`feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore`, `revert`), a lower-case scope, at most 72 characters, no trailing period, and a blank line before the body. Merge, revert, `fixup!`, `squash!` and `amend!` messages that git writes pass unchanged. It does not check body wrapping, so long URLs and logs can go in a body.

## Starting a new project

1. Grill the plan, then copy `templates/kickoff.md` to `docs/kickoff.md` and fill it in before writing code.
2. Copy `templates/AGENTS.md`, `templates/CLAUDE.md` and `templates/decisions.md` (as `docs/decisions.md`).
3. Install the commit hook and set up CI.

## Updating

- Rules: edit in this repo, commit under its own hook, push, and `git pull` on other machines. A new session picks up the change.
- Skills: `./scripts/sync-skills.sh`, review `git diff skills/`, run the tests, commit, then `./scripts/install-skills.sh`. See [`skills/README.md`](skills/README.md).
- Escalations: the coordinating agent appends entries to `escalation-log.md` and pushes them.

## Tests

`make test` (or `./tests/run.sh`) runs the shell tests: a table of good and bad commit messages for the hook, both install modes end to end, and the skill sync, overlay and install scripts against a local fake upstream. `make lint` runs ShellCheck. CI runs both on every push.

## Licence

MIT, see [`LICENSE`](LICENSE). The grill skills in `skills/` are by Matt Pocock ([mattpocock/skills](https://github.com/mattpocock/skills)) and stay under their own MIT licence in [`skills/LICENSE`](skills/LICENSE).
