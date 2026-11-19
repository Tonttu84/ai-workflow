#!/usr/bin/env bash
# Installs the ai-workflow commit-msg and pre-push hooks into a git
# project, with check-commits, which pre-push and the CI commit check
# both use to check the messages of a range of commits, and
# check-walkthrough, which pre-push runs in a project with feature files.
# A push to main or the default branch also runs the project's gate:
# the command of gate.conf, committed at the top of the repository
# (templates/gate.conf; hooks/pre-push explains it). It refuses the push
# without one, so the installer reminds you when the project has none.
#
# Usage: install.sh [--git-hooks | --copy-only] [--gate] [--force]
#                   [project-dir]
#
#   default      copy the hooks to <project>/.githooks/ and run
#                git config core.hooksPath .githooks. Commit .githooks/
#                so every clone gets the same hook; each clone still runs
#                the git config line once (put it in the setup command).
#                Stages the hooks as executable (100755): chmod does not
#                reach the index under core.filemode=false (Windows).
#                Adds `.githooks/* text eol=lf` to .gitattributes unless
#                a rule already gives them LF: bash rejects CRLF hooks.
#                Refuses when .git/hooks holds hooks (pre-commit, husky,
#                lefthook, Git LFS), since git would stop running them,
#                and warns when it overrides a global core.hooksPath.
#   --git-hooks  copy the hooks into the clone's own hooks directory
#                (.git/hooks) instead. Per clone only: nothing to commit
#                but the record (below).
#   --copy-only  copy the hooks to .githooks/, stage them as executable
#                and add the LF rule, as the default mode does, but leave
#                core.hooksPath alone: for husky projects, whose
#                .husky/pre-push calls .githooks/pre-push (see README).
#   --force      replace a commit-msg that is not ours, or another hooks
#                path, or switch off the hooks in .git/hooks. An older
#                commit-msg of ours, known by its Source line, is
#                replaced without it. A pre-push that is not ours
#                (Git LFS has one) is never replaced, even with --force:
#                it is kept as pre-push.local, and ours runs it first.
#                With --force the record also takes this install over
#                lines that a clone older than the record, or a squashed
#                ai-workflow branch, left (compare by hand first).
#   --gate       also copy the push-gate scripts to <project>/.ai-workflow/
#                (check-features.sh, the checks it runs, their awk
#                helpers and stryker-mutate-ranges.sh), stage them, the
#                scripts as executable, and add `.ai-workflow/* text
#                eol=lf` unless a rule already gives them LF. Commit
#                .ai-workflow/: the project gate and every clone then
#                run .ai-workflow/check-features.sh with no path to an
#                ai-workflow clone (and so can the CI job of
#                templates/feature-check.yml). Put that command in
#                gate.conf's command. Rerun it to update them; it
#                replaces the copies. Works with every mode.
#
# Every mode records what it copied, with this clone's commit, in the
# project's .ai-workflow-copies and stages it; commit it.
# scripts/check-drift.sh compares the project with the clone from it
# (D153). No install records the upgrade notes (docs/upgrading.md) as
# followed; scripts/copy-template.sh --notes-followed does (D156).
#
# Node projects may use commitlint and husky instead of this hook, with
# templates/commitlint.config.mjs from the same repository.
set -eu

mode=hookspath
force=0
gate=0
dir=.
while [ $# -gt 0 ]; do
  case $1 in
    --git-hooks | --copy-only)
      new=githooks
      [ "$1" = --copy-only ] && new=copyonly
      if [ "$mode" != hookspath ] && [ "$mode" != "$new" ]; then
        echo "install.sh: --git-hooks and --copy-only exclude each other" >&2
        exit 2
      fi
      mode=$new ;;
    --force) force=1 ;;
    --gate) gate=1 ;;
    -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    -*) echo "install.sh: unknown option $1" >&2; exit 2 ;;
    *) dir=$1 ;;
  esac
  shift
done

here="$(cd "$(dirname "$0")" && pwd)"
HOOKS="commit-msg pre-push check-commits check-walkthrough"
GATE="check-features.sh check-locked-tests.sh check-red-green.sh check-test-count.sh check-trace-links.sh stryker-mutate-ranges.sh feature-tables.awk junit-cases.awk"

if ! git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
  echo "install.sh: $dir is not inside a git repository" >&2
  exit 1
fi
top=$(git -C "$dir" rev-parse --show-toplevel)

# ai_workflow_hook <file>: the file is a version of one of our hooks
ai_workflow_hook() {
  grep -q '^# Source: https://github.com/Tonttu84/ai-workflow' "$1" 2> /dev/null
}

# install_hooks <directory>: copies every hook there. A commit-msg that is
# not ours is replaced only with --force; an older one of ours, known by
# its Source line, is replaced as pre-push is. A pre-push that is not
# ours (Git LFS installs one) is never replaced: it is kept as
# pre-push.local and ours runs it first. Every refusal comes before
# anything changes.
install_hooks() {
  local chain=0
  if [ -e "$1/commit-msg" ] && ! cmp -s "$here/commit-msg" "$1/commit-msg" &&
    ! ai_workflow_hook "$1/commit-msg" && [ "$force" -eq 0 ]; then
    echo "install.sh: $1/commit-msg exists and is not ours; rerun with --force to replace it" >&2
    exit 1
  fi
  if [ -e "$1/pre-push" ] && ! ai_workflow_hook "$1/pre-push"; then
    if [ -e "$1/pre-push.local" ]; then
      echo "install.sh: $1 holds both a pre-push that is not ours and a pre-push.local;" >&2
      echo "  merge them into pre-push.local, then rerun" >&2
      exit 1
    fi
    chain=1
  fi
  mkdir -p "$1"
  if [ "$chain" -eq 1 ]; then
    mv "$1/pre-push" "$1/pre-push.local"
    echo "Kept the existing pre-push as $1/pre-push.local; ours runs it first."
  fi
  for name in $HOOKS; do
    cp "$here/$name" "$1/$name"
    chmod +x "$1/$name"
  done
}

# index_exec: stages the hooks in .githooks/ as executable (100755). With
# core.filemode=false, as Git for Windows sets it, chmod never reaches the
# index, and git on Linux skips a hook committed as 100644. Checked with
# git ls-files -s; on failure it prints the command to run by hand.
index_exec() {
  local name f ok=1 files=()
  for name in $HOOKS pre-push.local; do
    [ -e "$top/.githooks/$name" ] && files+=(".githooks/$name")
  done
  local err
  err=$(git -C "$top" update-index --add --chmod=+x -- "${files[@]}" 2>&1) || ok=0
  for f in "${files[@]}"; do
    [ "$(git -C "$top" ls-files -s -- "$f" | cut -d ' ' -f 1)" = 100755 ] || ok=0
  done
  if [ "$ok" -eq 0 ]; then
    echo "install.sh: could not stage the hooks as executable:" >&2
    [ -z "$err" ] || printf '%s\n' "$err" | sed 's/^/  /' >&2
    echo "  Fix the cause and rerun install.sh (safe to repeat), or in $top run" >&2
    echo "  git update-index --add --chmod=+x -- ${files[*]}" >&2
    echo "  and check that git ls-files -s .githooks shows 100755 for each" >&2
    exit 1
  fi
  echo "Staged ${files[*]} as executable (100755 in git ls-files -s .githooks)."
}

# eol_of <path>: the line ending the project's own .gitattributes files
# give the path on checkout. Only those reach other clones, so git runs
# with an empty repository as its git dir (no .git/info/attributes), an
# empty core.attributesFile and no system attributes.
eol_of() {
  local scratch eol
  scratch=$(mktemp -d)
  git init -q --bare "$scratch/repo.git"
  : > "$scratch/empty"
  eol=$(cd "$top" && GIT_ATTR_NOSYSTEM=1 git --git-dir="$scratch/repo.git" --work-tree="$top" \
    -c core.attributesFile="$scratch/empty" check-attr eol -- "$1" |
    sed 's/^.*: //')
  rm -rf "$scratch"
  printf '%s\n' "$eol"
}

# lf_rule <dir> <file>: makes git check the files in the directory (the
# hooks, or the gate scripts) out with LF endings, which bash needs; a
# core.autocrlf=true clone writes CRLF unless .gitattributes says
# otherwise. Adds nothing when a rule (such as `* text=auto eol=lf`)
# already does it; the file is one to ask git about. Runs before
# anything is staged, so the index gets LF.
lf_rule() {
  local attrs="$top/.gitattributes" rule="$1/* text eol=lf"
  [ "$(eol_of "$1/$2")" = lf ] && return 0
  if [ -s "$attrs" ] && [ -n "$(tail -c 1 "$attrs")" ]; then echo >> "$attrs"; fi
  echo "$rule" >> "$attrs"
  echo "Added '$rule' to $attrs so clones check $1/ out with LF endings. Commit it."
  if [ "$(eol_of "$1/$2")" != lf ]; then
    echo "install.sh: warning: git still does not take $1/ as LF;" >&2
    echo "  check .gitattributes files (git check-attr eol -- $1/$2)" >&2
  fi
}

# ours <file>: the file is one of the hooks this script installs
ours() {
  local name
  for name in $HOOKS; do cmp -s "$here/$name" "$1" && return 0; done
  return 1
}

# The clone's own hooks directory (.git/hooks, shared by worktrees). Only
# meaningful while core.hooksPath is unset: git-path follows it otherwise.
hooks_dir() {
  local h
  h=$(cd "$top" && git rev-parse --git-path hooks)
  case $h in /* | [A-Za-z]:*) ;; *) h="$top/$h" ;; esac
  printf '%s\n' "$h"
}

# install_gate: copies the push-gate scripts to .ai-workflow/ (--gate),
# with the LF rule, and stages them: the scripts as executable (100755),
# the awk files as plain files. Checked with git ls-files -s.
install_gate() {
  local dest="$top/.ai-workflow" name f err ok=1 scripts=() others=()
  for name in $GATE; do
    [ -f "$here/../scripts/$name" ] || { echo "install.sh: $here/../scripts/$name not found" >&2; exit 1; }
  done
  mkdir -p "$dest"
  for name in $GATE; do
    cp "$here/../scripts/$name" "$dest/$name"
    case $name in
      *.sh) chmod +x "$dest/$name"; scripts+=(".ai-workflow/$name") ;;
      *) others+=(".ai-workflow/$name") ;;
    esac
  done
  lf_rule .ai-workflow check-features.sh
  err=$({ git -C "$top" update-index --add --chmod=+x -- "${scripts[@]}" &&
    git -C "$top" update-index --add --chmod=-x -- "${others[@]}"; } 2>&1) || ok=0
  for f in "${scripts[@]}"; do
    [ "$(git -C "$top" ls-files -s -- "$f" | cut -d ' ' -f 1)" = 100755 ] || ok=0
  done
  for f in "${others[@]}"; do
    [ -n "$(git -C "$top" ls-files -s -- "$f")" ] || ok=0
  done
  if [ "$ok" -eq 0 ]; then
    echo "install.sh: could not stage the gate scripts:" >&2
    [ -z "$err" ] || printf '%s\n' "$err" | sed 's/^/  /' >&2
    echo "  Fix the cause and rerun install.sh --gate (safe to repeat)." >&2
    exit 1
  fi
  echo "Copied the gate scripts to $dest and staged them (the scripts as 100755). Commit .ai-workflow/."
  echo "The gate runs, before a push to main or the merge of a pull request: .ai-workflow/check-features.sh --base origin/main, with feature-checks.conf; put it in gate.conf's command."
}

# record_install: lists what this run copied, with this clone's commit,
# in the project's .ai-workflow-copies and stages it (copy-template.sh
# --record); check-drift.sh reads it. It never records the upgrade notes
# as followed: only copy-template.sh --notes-followed does (D156).
RECORD=.ai-workflow-copies
HELPER="$here/../scripts/copy-template.sh"
# The record lines of this run, "<path here> <path in the project>" pairs,
# and --force for the helper with install.sh --force: it then records
# over lines a clone older than the record, or a squashed ai-workflow
# branch, left (D168).
pairs=()
dest_dir=.githooks
[ "$mode" != githooks ] || dest_dir=.git/hooks
for name in $HOOKS; do pairs+=("hooks/$name" "$dest_dir/$name"); done
if [ "$gate" -eq 1 ]; then
  for name in $GATE; do pairs+=("scripts/$name" ".ai-workflow/$name"); done
fi
record_flags=()
[ "$force" -eq 0 ] || record_flags=(--force)
record_install() {
  if ! bash "$HELPER" --record ${record_flags[@]+"${record_flags[@]}"} "$top" "${pairs[@]}" > /dev/null; then
    echo "install.sh: could not record the install in $top/$RECORD;" >&2
    echo "  fix the cause and rerun install.sh (safe to repeat)" >&2
    exit 1
  fi
  echo "Recorded the install in $top/$RECORD and staged it. Commit it."
}

# The record must take this run before anything changes: a clone older
# than the record would copy older hooks first and refuse after.
if ! bash "$HELPER" --record --dry-run ${record_flags[@]+"${record_flags[@]}"} "$top" "${pairs[@]}"; then
  echo "install.sh: nothing was installed or changed" >&2
  exit 1
fi

if [ "$mode" = hookspath ]; then
  current=$(git -C "$top" config --local --get core.hooksPath || true)
  effective=$(git -C "$top" config --get core.hooksPath || true)
  if [ -n "$current" ] && [ "$current" != .githooks ] && [ "$force" -eq 0 ]; then
    echo "install.sh: core.hooksPath is already '$current'; add the hook there" >&2
    echo "  (husky: --copy-only, see the README), use --git-hooks, or rerun with" >&2
    echo "  --force to switch to .githooks" >&2
    exit 1
  fi
  if [ -z "$effective" ]; then
    # Setting core.hooksPath makes git ignore every hook in .git/hooks.
    hooks=$(hooks_dir)
    found=
    for f in "$hooks"/*; do
      [ -f "$f" ] || continue
      case $f in *.sample) continue ;; esac
      ours "$f" && continue
      found="$found ${f##*/}"
    done
    if [ -n "$found" ] && [ "$force" -eq 0 ]; then
      echo "install.sh: $hooks holds hooks that core.hooksPath would switch off:$found" >&2
      echo "  use --git-hooks to install next to them, move them into .githooks/" >&2
      echo "  and rerun, or rerun with --force to switch them off" >&2
      exit 1
    fi
  elif [ -z "$current" ]; then
    echo "install.sh: warning: core.hooksPath '$effective' comes from your global" >&2
    echo "  or system git config; this repository now uses .githooks instead," >&2
    echo "  so the hooks in '$effective' stop running here" >&2
  fi
  install_hooks "$top/.githooks"
  lf_rule .githooks commit-msg
  index_exec
  git -C "$top" config core.hooksPath .githooks
  echo "Installed $HOOKS in $top/.githooks (core.hooksPath=.githooks). Commit .githooks/."
elif [ "$mode" = copyonly ]; then
  install_hooks "$top/.githooks"
  current=$(git -C "$top" config --get core.hooksPath || true)
  echo "Copied $HOOKS to $top/.githooks; core.hooksPath stays '${current:-unset}'. Commit .githooks/."
  echo "Call .githooks/pre-push \"\$@\" from the project's own pre-push (husky: .husky/pre-push)."
  lf_rule .githooks commit-msg
  index_exec
else
  current=$(git -C "$top" config --get core.hooksPath || true)
  if [ -n "$current" ]; then
    echo "install.sh: core.hooksPath is '$current', so git ignores .git/hooks;" >&2
    echo "  use the default mode instead" >&2
    exit 1
  fi
  hooks=$(cd "$top" && git rev-parse --git-path hooks)
  case $hooks in /* | [A-Za-z]:*) ;; *) hooks="$top/$hooks" ;; esac
  install_hooks "$hooks"
  echo "Installed $HOOKS in $hooks"
fi

if [ "$gate" -eq 1 ]; then install_gate; fi
record_install

# The pre-push hook refuses a push to main without a committed gate.conf.
if [ ! -f "$top/gate.conf" ]; then
  echo "Reminder: a push to main or the default branch runs the project's gate, and is refused until"
  echo "  gate.conf at the top of the repository declares it and is committed, for example:"
  echo "    command = make test lint"
  echo "  (templates/gate.conf in the ai-workflow clone explains its keys)."
fi
