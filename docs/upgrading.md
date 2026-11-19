# Upgrade notes

The one-time steps a project already migrated to these rules takes after a change here that no copied file shows: a repository setting or variable, a setup command, a file the project writes itself (D153). The hooks, the gate scripts and the templates a project copied are compared file by file by [`scripts/check-drift.sh`](../scripts/check-drift.sh); "Upgrading a migrated project" in [`rules/setup.md`](../rules/setup.md) is the procedure.

The check lists the entries added here after the commit in the `notes` line of the project's `.ai-workflow-copies`, and every entry, flagged as unknown, when the project has no such line. Once a project has followed them, record it: `bash <clone>/scripts/copy-template.sh --notes-followed <project>`, and commit the record.

Each entry is a heading `## YYYY-MM-DD: <what>`, dated by the change, then three items: From (the commit or decision that brought it), Do (what an already-migrated project does) and Done when (how to tell). Entries go oldest first. Add an entry in the same commit as the change it is about: the check dates an entry by the commit that added its heading here, so an entry added later is listed again even for projects that followed the change, a false alarm rather than a step missed (D60). A step that changes gets a new entry: an edited Do line under an old heading is never listed again (D157). No install records the notes as followed; a new or migrated project records them at the end of its setup (D156).

## 2026-11-10: Hooks committed as executable, with LF endings

- From: 81c61f4 and 5a7eae6 (`hooks/install.sh`).
- Do: rerun `hooks/install.sh` in the mode the project uses; it stages the hooks as `100755` and adds `.githooks/* text eol=lf` to `.gitattributes`. Commit both.
- Done when: `git ls-files -s .githooks` shows `100755` for every hook, and `git check-attr eol -- .githooks/commit-msg` ends in `lf`.

## 2026-11-10: COMMIT_CHECK_SINCE for the commit check

- From: 2d8b259 (`templates/commit-check.yml`); issue #2, where a scheduled check failed on messages from before the migration.
- Do: in a project with commits from before the rules, take the `commit-check.yml` that reads the variable (the drift check shows the template's change), then set the repository variable to the full SHA of the commit that added `.githooks/`: `gh variable set COMMIT_CHECK_SINCE --body <sha>`. A project that started under the rules leaves it unset.
- Done when: `gh variable list` shows `COMMIT_CHECK_SINCE` with that SHA, and a manual run of the commit check (`gh workflow run commit-check.yml`) passes.

## 2026-11-10: The PR title as the squash subject

- From: 2ce1e5f (`templates/commit-check.yml`).
- Do: a repository that squash-merges sets it once: `gh api -X PATCH repos/OWNER/REPO -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY`.
- Done when: `gh api repos/OWNER/REPO --jq .squash_merge_commit_title` prints `PR_TITLE`.

## 2026-11-16: check-walkthrough next to pre-push

- From: 61cbe50 and 44e16a6 (`hooks/check-walkthrough`, `hooks/pre-push`).
- Do: rerun `hooks/install.sh`, which copies `check-walkthrough` next to `pre-push`, and commit it. The newer `pre-push` refuses every push without it.
- Done when: the drift check reports no hook missing or different.

## 2026-11-16: Pull-request refs in a showcase project that squash-merges (D78)

- From: D78, written into `rules/setup.md` in a4b963d.
- Do: such a project adds the fetch of `refs/pull/*/head` to its setup command, as `rules/setup.md` shows, and runs it once in each clone.
- Done when: `git config --get-all remote.origin.fetch` lists `+refs/pull/*/head:refs/remotes/origin/pr/*`.

## 2026-11-17: The default branch recorded in each clone

- From: 6df6225 (`hooks/pre-push`), D121.
- Do: a repository created with `gh repo create --source . --push` runs `git remote set-head origin --auto` once in each clone. Without it, `pre-push` checks walkthroughs on every branch pushed.
- Done when: `git symbolic-ref refs/remotes/origin/HEAD` prints the default branch, such as `refs/remotes/origin/main`.

## 2026-11-18: The feature-check CI job in a public showcase project with feature files (D129, D137)

- From: D129 (08970a2), and `templates/feature-check.yml` from D137 (610e1fd).
- Do: copy `templates/feature-check.yml` to `.github/workflows/feature-check.yml` with `scripts/copy-template.sh`, fill in its toolchain step, record the job in the project's `docs/decisions.md`, and make `feature-check` a required check in the ruleset on `main`. A private showcase repository writes no job and runs both checks by hand before each merge (D133); other projects do nothing.
- Done when: the job passes on a pull request, and the ruleset on `main` requires `feature-check`.

## 2026-11-18: Branches up to date before a showcase merge (D141)

- From: f9548f2, D141.
- Do: in a project with the feature-check job, the ruleset's status-check rule that requires `feature-check` also turns on "Require branches to be up to date before merging".
- Done when: `gh api repos/OWNER/REPO/rulesets/<id>` shows `"strict_required_status_checks_policy": true` in its `required_status_checks` rule.

## 2026-11-18: A committed gate.conf, which pre-push runs (D142)

- From: b794b1b (`hooks/pre-push`) and bb5926d (`hooks/install.sh`), D142.
- Do: rerun `hooks/install.sh`. Copy `templates/gate.conf` to the top of the repository with `scripts/copy-template.sh`, set `command` to the project's whole local gate (tests, lint, types, build; with feature files, `.ai-workflow/check-features.sh --base origin/main` too) and commit it. A push to `main` then runs the gate and is refused without it, so give such a push a deadline longer than the gate's `timeout`.
- Done when: the drift check names neither `gate.conf` nor a hook, and `git push --dry-run origin main` runs the gate and passes.

## 2026-11-18: Claude Code's local files ignored in a committed .gitignore (D151)

- From: 1d03304 (`rules/setup.md`), D151.
- Do: a project worked on with Claude Code commits a `.gitignore` that ignores `.claude/worktrees/` and `.claude/settings.local.json`, and keeps `.claude/` out of every gate tool that finds files by itself (test discovery, a linter or type checker run on `.`).
- Done when: the drift check names neither path, and the gate, run with a worktree under `.claude/worktrees/`, reads none of its files.

## 2026-11-18: A dry-run push first with a slow gate (D152)

- From: 609a9bd and 2b9146a (`hooks/pre-push`), D152.
- Do: rerun `hooks/install.sh` for the `pre-push` that records a gate pass. With a gate that takes minutes, push to `main` with `git push --dry-run origin main` first, which runs and records the gate, then `git push origin main`, which skips the gate for that commit.
- Done when: the drift check reports no hook different, and a second push of a commit whose gate passed says it skips the gate.

## 2026-11-19: The record and the drift check (D153, D154)

- From: D153 and D154: `scripts/check-drift.sh`, `scripts/copy-template.sh` and the record `hooks/install.sh` writes.
- Do: rerun `hooks/install.sh`, which writes `.ai-workflow-copies`. Bring each template the check names up to date with the `scripts/copy-template.sh` command it gives, which passes the guessed commit as `--base` and records the copy. Record a copied template the check does not name, since nothing changed upstream since its guessed version, with `scripts/copy-template.sh --record`, so later checks need no guess. Follow the notes above, then record them with `scripts/copy-template.sh --notes-followed`, and commit.
- Done when: `bash <clone>/scripts/check-drift.sh <project>` reports no drift.
