#!/usr/bin/env bash
# Installs the ai-workflow commit-msg hook into a git project.
#
# Usage: install.sh [--git-hooks] [--force] [project-dir]
#
#   default      copy the hook to <project>/.githooks/commit-msg and run
#                git config core.hooksPath .githooks. Commit .githooks/
#                so every clone gets the same hook; each clone still runs
#                the git config line once (put it in the setup command).
#                Refuses when .git/hooks holds hooks (pre-commit, husky,
#                lefthook, Git LFS), since git would stop running them,
#                and warns when it overrides a global core.hooksPath.
#   --git-hooks  copy the hook into the clone's own hooks directory
#                (.git/hooks) instead. Nothing to commit; per clone only.
#   --force      replace a different existing hook or hooks path, or
#                switch off the hooks in .git/hooks.
#
# Node projects may use commitlint with @commitlint/config-conventional
# (and header-max-length 72) through husky instead of this hook.
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

src="$(cd "$(dirname "$0")" && pwd)/commit-msg"

if ! git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
  echo "install.sh: $dir is not inside a git repository" >&2
  exit 1
fi
top=$(git -C "$dir" rev-parse --show-toplevel)

# copy_hook <destination>: refuses to replace a different file without --force
copy_hook() {
  if [ -e "$1" ] && ! cmp -s "$src" "$1" && [ "$force" -eq 0 ]; then
    echo "install.sh: $1 exists and differs; rerun with --force to replace it" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$1")"
  cp "$src" "$1"
  chmod +x "$1"
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
      cmp -s "$src" "$f" && continue
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
  copy_hook "$top/.githooks/commit-msg"
  git -C "$top" config core.hooksPath .githooks
  echo "Installed $top/.githooks/commit-msg (core.hooksPath=.githooks). Commit .githooks/."
else
  current=$(git -C "$top" config --get core.hooksPath || true)
  if [ -n "$current" ]; then
    echo "install.sh: core.hooksPath is '$current', so git ignores .git/hooks;" >&2
    echo "  use the default mode instead" >&2
    exit 1
  fi
  hooks=$(cd "$top" && git rev-parse --git-path hooks)
  case $hooks in /* | [A-Za-z]:*) ;; *) hooks="$top/$hooks" ;; esac
  copy_hook "$hooks/commit-msg"
  echo "Installed $hooks/commit-msg"
fi
