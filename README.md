# ai-workflow

The working rules I use for every project I build with Claude Code and other AI coding tools: how work is planned, delegated to agents, tested, reviewed and committed. One rules file is loaded into every session; each project adds only what is specific to it.

These rules are how I keep AI-assisted work honest: decisions are written down, tests come first, every change is reviewed by an agent that did not write it, and commit messages are checked by a hook rather than by good intentions.

## How it is used

```text
~/.claude/CLAUDE.md                      one line: @<clone>/rules/working-agreements.md
└── rules/working-agreements.md          shared rules, loaded in every session and subagent

~/.claude/skills/                        installed from skills/, loaded when used
├── coordinating/                        the coordinator's procedure
├── researching/                         when and how to research
├── verifying-features/                  the feature pipeline
└── grilling/, grill-me/                 the grill skills, from upstream

rules/setup.md                           read when a project is started or migrated

<project>/CLAUDE.md                      one line: @AGENTS.md
└── <project>/AGENTS.md                  project specifics: its kind (solo or showcase),
                                         stack, commands, domain rules, quirks
```

- `rules/working-agreements.md` is the only file loaded into every session, subagents included, so it holds only what every agent needs: rules an agent does not need are noise for it, whatever they cost in tokens (D58). What only the coordinator needs (the session talking with the owner) lives in skills, which the rules file triggers in one line each; what only a new or migrating project needs lives in `rules/setup.md` (D88).
- Nothing a subagent needs lives only in a skill: it is in the rules file or in the template its brief comes from, since whether general-purpose subagents can use skills was not verified.
- A project's `AGENTS.md` holds only what is specific to that project and says which kind it is. Solo projects commit to `main` once the local gate (tests, lint, types, build) is green and run tier 1 of verification, alignment; showcase projects go through a pull request, a fresh-agent review and a squash-merge, and add tier 2, audit evidence (D59). `AGENTS.md` is the open format other coding tools read; its `CLAUDE.md` is the single line `@AGENTS.md`.
- Everything else here (templates, briefs, hooks, scripts, research reports) is used on demand.

## Layout

```text
rules/
  working-agreements.md       the shared rules, imported into every session
  setup.md                    the agents' steps for starting or migrating a project
templates/
  AGENTS.md                   a project rulebook skeleton
  CLAUDE.md                   the one line @AGENTS.md
  kickoff.md                  the plan written before any code
  decisions.md                the decision log (D1, D2, ...) with its Meta column
  escapes.md                  what got past the workflow, and the fix
  feature.md                  a feature's items, entry points, expected outcomes and walkthrough
  agent-brief.md              the brief for a coding subagent
  test-writer-brief.md        the brief for the agent that locks a feature's tests first
  trace-brief.md              the brief for a white-box trace of a feature
  blackbox-test-brief.md      the brief for a tester who uses the running app
  review-brief.md             the brief for a cold reviewer
  hardening-brief.md          the brief for the test hardening run after a feature
  research-brief.md           the brief for a research subagent
  openfasttrace.md            tracing feature items with OpenFastTrace
  function-limits.md          linter limits on function size, per stack
  data-science.md             leakage tests, baselines, metrics and model reports for data and ML projects
  commitlint.config.mjs       commitlint rules matching the hook, for Node projects
  commit-check.yml            CI gate: every commit message and PR title
  dependabot.yml              grouped dependency updates every two weeks
hooks/
  commit-msg                  portable bash hook enforcing the commit rules
  pre-push                    checks every commit being pushed, as CI does
  check-commits               the range check pre-push and CI share
  check-walkthrough           refuses a push while a finished feature lacks an owner walkthrough
  install.sh                  installs the hooks into a project
skills/                       see skills/README.md
  coordinating/               the coordinator's procedure (local)
  researching/                when and how to research (local)
  verifying-features/         the feature pipeline (local)
  grilling/, grill-me/        the grill skills, tracked from upstream
  overlays/                   the local changes re-applied to upstream skills
scripts/
  sync-skills.sh              fetches the latest upstream skills, re-applies local overlays
  apply-skill-overlay.sh      applies one overlay (used by sync-skills.sh)
  install-skills.sh           copies the skills to ~/.claude/skills
  decisions-due.sh            lists the decision rows due for a recheck
  check-locked-tests.sh       the locked tests are unchanged
  check-red-green.sh          the locked tests fail before the feature and pass after it
  check-test-count.sh         the test runner finished and no test was lost
  check-trace-links.sh        tests link to feature items at their current revision
  check-citations.sh          the path:line citations in a report resolve
  stryker-mutate-ranges.sh    turns a diff into StrykerJS mutate ranges
tests/                        shell tests for the hooks, the scripts and the docs (./tests/run.sh)
escalation-log.md             why some tasks needed a stronger model: a learning journal
docs/decisions.md             the decisions behind this repo
docs/research/                research reports on tools and practices, kept generic
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
- Do not pin a session `model` (D9). The coordinator runs a stronger model or effort than its subagents (D85): pick it when starting the coordinating session, for example with `/model`.

Passing `effort` on a subagent call needs Claude Code v2.1.292 or later.

### 4. Skills

```bash
./scripts/install-skills.sh      # copies skills/* to ~/.claude/skills (or $CLAUDE_CONFIG_DIR/skills)
```

It installs the grill skills and this repository's own `coordinating`, `researching` and `verifying-features`, which the rules file sends the coordinator to: without them the coordinator has only the one-line triggers. Run it again after every `git pull` that changes `skills/`.

Remove any per-project copies of `grilling` and `grill-me` (under a project's `.claude/skills/`) so the user-level copy is the one in use.

### 5. The commit hook in each project

This section and the next explain the hooks, the CI check and the repository settings; the steps an agent follows to set them up are in [`rules/setup.md`](rules/setup.md).

Projects without Node:

```bash
/path/to/ai-workflow/hooks/install.sh /path/to/project            # .githooks/ + core.hooksPath
/path/to/ai-workflow/hooks/install.sh --git-hooks /path/to/project  # or copy into .git/hooks
```

It installs two hooks: `commit-msg` checks a message as it is written, and `pre-push` checks every commit about to be pushed with the same range check the CI template runs, so a bad message is caught before the push, without spending Actions minutes. The default mode copies them to the project's `.githooks/` (commit it) and sets `core.hooksPath`. It also stages them as executable with `git update-index --add --chmod=+x` and checks that `git ls-files -s .githooks` shows `100755`: with `core.filemode=false`, as Git for Windows sets it, `chmod +x` never reaches the index, the hooks are committed as `100644`, and git on Linux and in web sessions skips them. And it adds `.githooks/* text eol=lf` to the project's `.gitattributes` (commit it) unless `git check-attr eol` shows that a rule such as `* text=auto eol=lf` already covers the hooks: a `core.autocrlf=true` clone otherwise checks them out with CRLF endings, which bash rejects. Each fresh clone still needs `git config core.hooksPath .githooks` once, so put that line in the project's setup command.

In a project with feature files (`docs/features/`, from [`templates/feature.md`](templates/feature.md)), `pre-push` also runs `check-walkthrough`, installed next to it, on each commit pushed. While every item of a feature is `functional`, the feature's `Walkthrough:` line must say `done YYYY-MM-DD at <commit>` (the commit the owner watched) or `skipped YYYY-MM-DD at <commit>: <reason>` (the commit whose items the owner decided not to watch; the reason is required). Either one goes stale, and the push is refused, once an item's Rev is bumped or an item is added after the commit it names: walk it again or record a new skip. The check reads the feature files as committed in the commit pushed, not the working tree, and a project without `docs/features/` is not affected.

Setting `core.hooksPath` makes git ignore every hook in `.git/hooks`, so the default mode refuses when that folder already holds hooks (pre-commit, husky, lefthook, Git LFS): use `--git-hooks`, move them into `.githooks/`, or pass `--force` to switch them off. It warns when it overrides a global `core.hooksPath`. Both modes refuse to replace a different `commit-msg` without `--force`. A `pre-push` that is not ours, such as Git LFS's, is never replaced, not even with `--force`: the installer keeps it as `pre-push.local`, and our `pre-push` runs it first with the same arguments and input, so LFS objects still go up. In the default mode, move an LFS project's hooks from `.git/hooks` into `.githooks/` before installing (`--force` would switch them off); `--git-hooks` chains in place.

Node projects may use [commitlint](https://commitlint.js.org) and husky instead, with [`templates/commitlint.config.mjs`](templates/commitlint.config.mjs). It extends `@commitlint/config-conventional` so that it accepts and rejects the same messages as the hook; its header lists the few differences.

#### A project that already uses husky

Husky sets `core.hooksPath` to `.husky/_`, so the default mode refuses. Keep husky as the hook runner:

1. `install.sh --copy-only /path/to/project` copies the four files to `.githooks/` unchanged, stages them as executable and adds the LF rule, as the default mode does, but leaves `core.hooksPath` alone. CI needs `.githooks/commit-msg` and `.githooks/check-commits`.
2. Call our `pre-push` from husky's, passing git's arguments; its input (the refs being pushed) passes through on its own. `.husky/pre-push`:

   ```sh
   .githooks/pre-push "$@"
   ```

3. Check messages as they are written with commitlint from `.husky/commit-msg` (`npx --no -- commitlint --edit "$1"`) and `templates/commitlint.config.mjs`.

The hook checks: a subject of the form `type(scope)!: summary` with an allowed type (`feat`, `fix`, `docs`, `test`, `refactor`, `perf`, `build`, `ci`, `chore`, `revert`), a lower-case scope, at most 72 characters, no trailing period, and a blank line before the body. Subjects that start the way git's own merge, revert, reapply, `fixup!`, `squash!` and `amend!` messages do pass unchecked, whether git wrote them or a person typed them; `templates/commit-check.yml` keeps `fixup!`, `squash!` and `amend!` commits off `main`. Comment lines count unless git drops them (it does in its editor, not with `-m` or `-F`), and the length is counted in characters. It does not check body wrapping, so long URLs and logs can go in a body.

### 6. CI: the gate for commit messages

The hook is feedback while writing, not a gate: `core.hooksPath` is local config that a clone does not copy, `--no-verify` and GitHub's web editor skip it, and a squash merge writes its commit on GitHub. Three layers:

1. The hooks catch a bad message as it is written (`commit-msg`) and before it is pushed (`pre-push`, the same check CI runs). Run them, with the tests, lint, types and build, before every push: Actions minutes are scarce on private repositories.
2. CI checks every commit that reaches `main` and every PR title: copy [`templates/commit-check.yml`](templates/commit-check.yml) to the project's `.github/workflows/`. This is the gate; it confirms now and then. Public repositories may run it on every push and pull request; private ones delete the push trigger and use the weekly schedule, pull requests and manual runs.
3. A ruleset on `main` makes the gate binding. In a repository that works through pull requests it requires the `commit-check` jobs and blocks force pushes. A solo repository pushes to `main` directly, which a required check would reject, so its ruleset only blocks force pushes and deletion of `main`, and CI stays visible there. On GitHub Free, rulesets work only on public repositories; a private repository is a recorded exception (the check is visible but does not block) until the plan changes.

A squash merge turns the PR title into the commit subject on `main`. By default GitHub does that only for pull requests with more than one commit; a one-commit PR gets that commit's subject. Make the PR title the subject in every case, once per repository:

```bash
gh api -X PATCH repos/OWNER/REPO \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY
```

The workflow runs the project's committed `.githooks/commit-msg`, as it was before the change, on every commit of a pull request (base to head) and of a push to `main` (before to after; for a new branch only the head), so a change cannot weaken its own check. Merge commits git writes pass; `fixup!`, `squash!` and `amend!` commits fail. It also checks the PR title and rejects titles the hook would let through as git's own messages (`Merge ...`, `Revert "..."`, `fixup! ...`). Actions are pinned by SHA, the runner is pinned (`ubuntu-24.04`, not `ubuntu-latest`), the token is read-only and not persisted, and the title reaches the script through an environment variable, never pasted into it.

A scheduled or manual run checks the last 15 days along the branch. In a project with older history, that would fail on messages written before the rules: set the repository variable `COMMIT_CHECK_SINCE` to the full SHA of the commit that added `.githooks/` (`gh variable set COMMIT_CHECK_SINCE --body <sha>`). That commit and its ancestors are never checked, and its hook checks the commits after it. The value reaches the script through an environment variable and must be a full SHA, or the run fails.

## Starting or moving a project

The coordinating agent follows [`rules/setup.md`](rules/setup.md), which the rules file points to:

- A new project starts with a grill and a `docs/kickoff.md` written before any code, then the project's `AGENTS.md`, `docs/decisions.md` and `docs/escapes.md`, the hooks, CI, the repository settings, Dependabot and the function limits.
- An existing project is moved from a fresh `git fetch`, with the identity its history already uses, keeping its own rules until the owner decides on each; its committed test secrets move to the private repository and are rotated.
- A data or ML project also follows `templates/data-science.md`.

## Updating

- Rules: edit in this repo, commit under its own hook, push, and `git pull` on other machines. A new session picks up the change. Keep `rules/working-agreements.md` to what every agent needs; the coordinator's procedure goes in a local skill, setup steps in `rules/setup.md`.
- Skills: the local skills are edited here like any file; the grill skills come from upstream with `./scripts/sync-skills.sh`, then review `git diff skills/` and run the tests. Commit, then `./scripts/install-skills.sh` on every machine. See [`skills/README.md`](skills/README.md).
- Escalations: the coordinating agent appends entries to `escalation-log.md`, commits that file alone and pushes it.

## Tests

`make test` (or `./tests/run.sh`) runs the shell tests: a table of good and bad commit messages for the hook plus real `git commit` runs through it, both install modes end to end, the walkthrough check on throwaway repositories and through real pushes, the feature-check and decision scripts on throwaway repositories, the skill sync, overlay and install scripts against a local fake upstream (a sync leaves the local skills alone, and the install copies them), the templates that must match the hook and the shape of their tables, and the docs: the rules file's 2,000-word cap (D89), its triggers for the local skills and `rules/setup.md`, the rules a subagent needs staying in it, and every template, hook, script, rules or skills path that the rules, the setup file, the skills, the templates and this readme name. `make lint` runs [ShellCheck](https://www.shellcheck.net), which must be installed. CI runs both on pushes to `main` and on pull requests.

## Licence

MIT, see [`LICENSE`](LICENSE); that covers the local skills in `skills/` too. The grill skills in `skills/` are by Matt Pocock ([mattpocock/skills](https://github.com/mattpocock/skills)) and stay under their own MIT licence in [`skills/LICENSE`](skills/LICENSE).
