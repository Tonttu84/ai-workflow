#!/usr/bin/env bash
# Installs the ai-workflow commit-msg and pre-push hooks into a git
# project, with check-commits, which pre-push and the CI commit check
# both use to check the messages of a range of commits.
#
# Usage: install.sh [--git-hooks] [--force] [project-dir]
#
#   default      copy the hooks to <project>/.githooks/ and run
#                git config core.hooksPath .githooks. Commit .githooks/
#                so every clone gets the same hook; each clone still runs
#                the git config line once (put it in the setup command).
#                Refuses when .git/hooks holds hooks (pre-commit, husky,
#                lefthook, Git LFS), since git would stop running them,
#                and warns when it overrides a global core.hooksPath.
#   --git-hooks  copy the hooks into the clone's own hooks directory
#                (.git/hooks) instead. Nothing to commit; per clone only.
#   --force      replace a different commit-msg or hooks path, or switch
#                off the hooks in .git/hooks. A pre-push that is not ours
#                (Git LFS has one) is never replaced, even with --force:
#                it is kept as pre-push.local, and ours runs it first.
#
# Node projects may use commitlint and husky instead of this hook, with
# templates/commitlint.config.mjs from the same repository.
set -eu

mode=hookspath
force=0
dir=.
while [ $# -gt 0 ]; do
  case $1 in
    --git-hooks) mode=githooks ;;
    --force) force=1 ;;
    -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    -*) echo "install.sh: unknown option $1" >&2; exit 2 ;;
    *) dir=$1 ;;
  esac
  shift
done

here="$(cd "$(dirname "$0")" && pwd)"
HOOKS="commit-msg pre-push check-commits"

if ! git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
  echo "install.sh: $dir is not inside a git repository" >&2
  exit 1
fi
top=$(git -C "$dir" rev-parse --show-toplevel)

# ai_workflow_hook <file>: the file is a version of one of our hooks
ai_workflow_hook() {
  grep -q '^# Source: https://github.com/Tonttu84/ai-workflow' "$1" 2> /dev/null
}

# install_hooks <directory>: copies every hook there. A different
# commit-msg is replaced only with --force. A pre-push that is not ours
# (Git LFS installs one) is never replaced: it is kept as pre-push.local
# and ours runs it first. Every refusal comes before anything changes.
install_hooks() {
  local chain=0
  if [ -e "$1/commit-msg" ] && ! cmp -s "$here/commit-msg" "$1/commit-msg" && [ "$force" -eq 0 ]; then
    echo "install.sh: $1/commit-msg exists and differs; rerun with --force to replace it" >&2
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

if [ "$mode" = hookspath ]; then
  current=$(git -C "$top" config --local --get core.hooksPath || true)
  effective=$(git -C "$top" config --get core.hooksPath || true)
  if [ -n "$current" ] && [ "$current" != .githooks ] && [ "$force" -eq 0 ]; then
    echo "install.sh: core.hooksPath is already '$current'; add the hook there," >&2
    echo "  use --git-hooks, or rerun with --force to switch to .githooks" >&2
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
  git -C "$top" config core.hooksPath .githooks
  echo "Installed $HOOKS in $top/.githooks (core.hooksPath=.githooks). Commit .githooks/."
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
