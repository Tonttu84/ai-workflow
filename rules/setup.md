# Project setup

The steps for an agent starting a new project or moving an existing one to the working agreements. Paths such as `templates/`, `hooks/` and `scripts/` are in the ai-workflow clone that holds this file. The [README](../README.md) explains the hooks, the CI check and the repository settings for a human reader; this file is the procedure.

Repositories the owner does not own, and the owner's inactive repositories that were never migrated, get none of this (the opening rule of the working agreements).

## Kickoff (new project)

1. Grill the owner (the `grilling` skill) about the goal, the users, the scope and the kind: solo or showcase. Every project gets tier 1 (alignment). A showcase project adds tier 2 (audit evidence) as a bonus: today, the review metrics drawn from the planted-bug record every project keeps (D80) and, in one showcase project with feature files that the owner chooses, OpenFastTrace tracing (D91, D117, `templates/openfasttrace.md`); ask the owner whether this is that project. `templates/AGENTS.md` says what each tier covers.
2. Write `docs/kickoff.md` from `templates/kickoff.md` before any code.
3. The stack is discussed every time. Open with a proposal:
   - Web app: TypeScript (strict), Next.js, Tailwind, Prisma, Zod, Vitest, Playwright.
   - Compiled: Rust first. C++ when the project needs its libraries, a game engine or an embedded toolchain.
   - Python (uv, FastAPI, pydantic, pytest, ruff, pyright strict in the gate and CI) for services, scripts and data work, but not by default when the project would benefit from a compiled language.
   - Testing tools are the agent's choice; put one to the owner only when there is a real trade-off to weigh, not just a pick between equals.
4. Copy from `templates/`: `AGENTS.md` (state the kind, and whether the project uses feature files), `CLAUDE.md` (the one line `@AGENTS.md`), `decisions.md` as `docs/decisions.md` and `escapes.md` as `docs/escapes.md` (`templates/escapes.md`).
5. Install the hooks (with `--gate` if the project uses feature files) and commit the project's `gate.conf` (below), then set up CI, the repository settings and Dependabot: the sections below.
6. Turn on the function limits from `templates/function-limits.md` at the starting values, as warnings; make them errors once the first code settles.
7. Test credentials: commit the variable names with empty values; the values live in the private repository under `<project>/credentials/`.
8. A data or ML project: point `AGENTS.md` at `templates/data-science.md` by its GitHub URL and state the project's split, metric and baseline there.

## Migrating an existing project

1. Start from what is on GitHub, not from the local `main`: `git fetch origin`, then base the work on `origin/<default branch>` (a new branch or worktree from it). `git status` compares with the last fetch, so "up to date" can hide a `main` many commits behind; that happened in three migrations.
2. Commit with the identity the project's history on origin already uses (`git log -5 --format='%an <%ae>' origin/<default branch>`), set with `git config user.name` and `user.email` in that clone, not the machine's global one.
3. Add `AGENTS.md` (stating the kind, and whether the project uses feature files), the one-line `CLAUDE.md`, `docs/decisions.md` and `docs/escapes.md` from `templates/`. A team repository with several collaborators is showcase (pull requests) unless the owner says otherwise. Where the project already has rules of its own that the shared rules would replace, keep them and list each for the owner, with the shared rule that would replace it: dropping a project's rule is the owner's decision, not the agent's.
4. Install the hooks (below; with `--gate` if the project uses feature files) and add the `git config` line to the setup command (not with `--copy-only`): a fresh clone has the hooks off until that runs. Commit `.githooks/`, `.gitattributes` and the project's `gate.conf` (below), then check that `git ls-files -s .githooks` shows `100755` for every hook: git on Linux skips a hook committed as `100644`.
5. Smoke-check it in that repository: a bad message is rejected (`git commit --allow-empty -m "bad"`), a good one passes, and the project's existing hooks (pre-commit, Git LFS, husky) still run.
6. Once the hook is committed and on `main`, add `templates/commit-check.yml` (a change that adds both is checked with its own copy of the hook, with a warning) and the repository settings (below). Set the repository variable `COMMIT_CHECK_SINCE` to the full SHA of the commit that added `.githooks/` (`gh variable set COMMIT_CHECK_SINCE --body <sha>`), so manual and scheduled runs skip the messages written before the rules. The first pull request, or a manual run, should show the commit check running and passing.
7. Turn on Dependabot (below).
8. Set the function limits (`templates/function-limits.md`): turn the linter checks on as warnings (in a separate report-only config if the lint gate allows no warnings), measure the existing code, pick limits that flag only the worst few percent, record them in `docs/decisions.md`, then make them errors.
9. Move committed test secrets into the private repository (`<secrets>/<project>/credentials/<file>`), leaving their variable names with empty values in the project, and rotate every moved value at its provider: git history keeps the old ones.
10. A data or ML project: point `AGENTS.md` at `templates/data-science.md` by its GitHub URL (collaborators may not have the clone) and add the leakage tests it lists.

## The hooks

- Install with `hooks/install.sh /path/to/project`: it copies `commit-msg`, `pre-push` and their helpers to `.githooks/`, sets `core.hooksPath`, stages them as executable and adds the LF rule to `.gitattributes`. `--git-hooks` copies into `.git/hooks` instead. When it refuses (hooks already in `.git/hooks`, a different `commit-msg`), read the README's "The commit hook in each project" before reaching for `--force`.
- A project that already uses husky keeps it: `install.sh --copy-only` and the README's husky recipe.
- Node projects may use commitlint and husky with `templates/commitlint.config.mjs` instead of `commit-msg`.
- The setup command runs `git config core.hooksPath .githooks`: a fresh clone has the hooks off until it does.
- The gate: copy `templates/gate.conf` to the top of the repository, set `command` to the project's whole local gate (tests, lint, types, build) and commit it. Before a push to `main` or the default branch, the pre-push hook runs that command at the top of the repository, after the message and walkthrough checks, and refuses the push when it fails, a missing tool included, when it passes its `timeout` (default 3600 seconds, at most 86400), when `gate.conf` is missing, or when the working tree, submodules included, is not the commit pushed, before the gate or after it (D142). So the gate must leave the tree alone: a check mode, not `--fix`, and its outputs ignored in a committed `.gitignore`. Its input is `/dev/null` and git's pager and credential prompt are off, but a step that opens the terminal itself, such as an ssh passphrase prompt, waits until the deadline, so nothing in it may prompt. With no default branch recorded, `master` is gated as well as `main`. A push to another branch never runs it (D128). There is no switch to skip it, so whoever pushes to `main`, an agent included, gives the push command a deadline longer than the gate's `timeout`.
  - Only a committed `.gitignore` hides an untracked file from that check; `.git/info/exclude` and a global excludes file do not count (D151).
  - Claude Code keeps its worktrees, full checkouts of other branches, in `.claude/worktrees/` inside the repository, and lists them only in `.git/info/exclude`. A project worked on with it commits a `.gitignore` that ignores `.claude/worktrees/` and `.claude/settings.local.json`.
  - It also keeps `.claude/` out of every gate tool that finds files by itself: test discovery, a linter or type checker run on `.`. Otherwise the gate runs the other branches' tests too, and their locked tests are red by design (D128).
- The pre-push hook checks walkthroughs only on pushes to the default branch, which it reads from `refs/remotes/origin/HEAD`. `git clone` records it; a repository created with `gh repo create --source . --push` does not, so run `git remote set-head origin --auto` once there, or every branch pushed is checked (tags always are).
- A project with feature files: `hooks/install.sh --gate` also copies the push-gate scripts (`check-features.sh`, the checks it runs, their awk helpers and `stryker-mutate-ranges.sh`) into the project's `.ai-workflow/` and stages them; commit it. Then:
  - Add a committed `feature-checks.conf` at the top of the repository (its keys are in `templates/AGENTS.md` and `.ai-workflow/check-features.sh --help`).
  - Turn on the test runner's JUnit reporter, so that `run` writes the reports, and create the count file that lists them (its format: `.ai-workflow/check-test-count.sh --help`). Each report is deleted before the run, so its path must be inside the repository and untracked; ignore it in a committed `.gitignore`, since the gate fails on an untracked file nothing ignores.
  - Put `.ai-workflow/check-features.sh --base origin/main` in the gate (the `command` of `gate.conf`), which runs before a push to `main` or the merge of a pull request, never on a push to another branch (D114, D128).
  - The project then needs no path to an ai-workflow clone, for collaborators or a future CI job (D101). Rerun `--gate` to update the copies when the scripts change.
- The feature checks need each locked commit and `origin/main` in the clone, so a clone or CI job that runs the gate needs full history (`actions/checkout` with `fetch-depth: 0`) and, in a repository that squash-merges, the pull-request refs (D78, below); otherwise they die with "unknown commit".
- Scheduled mutation testing in CI (D75) is deferred until the first project with feature files sets up its CI (D100, confirmed by the owner in D116 and again in D137, which built only the gate's job): that project writes the mutation workflow, with D39's triggers for a private repository (by hand and on a schedule), and records it. Until then mutation testing runs only in the hardening step.

## CI and repository settings

- Copy `templates/commit-check.yml` to `.github/workflows/`. It is the gate for commit messages and confirms the local check: public repositories run it on every push and pull request; private ones, short of Actions minutes, delete the push trigger and run it on pull requests, by hand (`workflow_dispatch`) and on its schedule.
- A ruleset on `main` blocks force pushes and deletion. In a repository that works through pull requests it also requires the `commit-check` jobs; a solo repository's does not, since a required check would reject its direct pushes. GitHub Free offers rulesets only on public repositories, so private ones have none (a recorded exception).
- So in a private solo repository: the local gate before every push to `main` (run by `pre-push` from `gate.conf`), `pre-push`'s commit check on every push, CI by hand and on a schedule, no ruleset.
- A repository that squash-merges sets the PR title as the squash subject, once: `gh api -X PATCH repos/OWNER/REPO -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY`. By default a one-commit PR gets that commit's subject instead.
- A showcase project that squash-merges fetches pull-request refs in its setup command, so the commit a walkthrough names stays findable after the merge deletes its branch:

  ```sh
  git config --get-all remote.origin.fetch | grep -qF 'refs/pull/' ||
    git config --add remote.origin.fetch '+refs/pull/*/head:refs/remotes/origin/pr/*'
  git fetch origin
  ```

- A showcase project with feature files adds a CI job as part of its setup, before its first feature pull request merges (D129):
  - A merge on GitHub runs no local hook. Without the job, nothing enforces the feature checks and the walkthrough check before a showcase project's merge.
  - The job runs on pull requests, on the pull request's head. It runs `.ai-workflow/check-features.sh --base origin/main` and the walkthrough check, `check-walkthrough HEAD`. The check scripts come from the pull request's base, so editing them in the pull request does not switch them off. The workflow, `feature-checks.conf`, the tests and `docs/features/` come from the pull request; D59 accepts that, since tier 1 does not guard against tampering.
  - It needs full history and the pull-request refs (above). It is a required check in the ruleset on `main`.
  - The ruleset's status-check rule also turns on "Require branches to be up to date before merging" (D141). A pull request behind `main` then cannot merge until it is updated and checked again.
  - It needs the hooks committed in `.githooks/`: the default mode of `hooks/install.sh`, or `--copy-only` under husky. A `--git-hooks` install commits none.
  - The project copies `templates/feature-check.yml` to `.github/workflows/` and fills in its toolchain step, the one step that depends on the stack (D137). Until then that step fails the job.
  - The toolchain step installs the toolchain and the dependencies, into paths a committed `.gitignore` ignores. The checks run the tests in the working tree, where the config's `setup` never runs.
  - The project records the job as a row in its `docs/decisions.md`. The check to require is `feature-check`, the job's name.
  - Public repositories get required checks and Actions minutes free on GitHub Free.
  - A private showcase repository writes no job: its Actions minutes are scarce (D39), and GitHub Free cannot require the check there. The coordinator runs both checks by hand before each merge, and the project's `AGENTS.md` says so.
  - Until the job exists, the coordinator runs both checks by hand before each merge (the `verifying-features` skill, step 12).

## Dependabot

- Security updates are on in every repository, private ones too: Settings, Code security, Dependabot security updates.
- Version updates: copy `templates/dependabot.yml` to `.github/dependabot.yml`, uncomment the project's ecosystems and delete the examples it does not use. A repository with nothing to update (such as a private secrets repository) skips version updates.
