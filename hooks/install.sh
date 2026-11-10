#!/usr/bin/env bash
# Installs the ai-workflow commit-msg hook into a git project.
#
# Usage: install.sh [--git-hooks] [--force] [project-dir]
#
#   default      copy the hook to <project>/.githooks/commit-msg and run
#                git config core.hooksPath .githooks. Commit .githooks/
#                so every clone gets the same hook; each clone still runs
#                the git config line once (put it in the setup command).
#   --git-hooks  copy the hook into the clone's own hooks directory
#                (.git/hooks) instead. Nothing to commit; per clone only.
#   --force      replace a different existing hook or hooks path.
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
    -h | --help) sed -n '2,17p' "$0"; exit 0 ;;
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

if [ "$mode" = hookspath ]; then
  current=$(git -C "$top" config --local --get core.hooksPath || true)
  if [ -n "$current" ] && [ "$current" != .githooks ] && [ "$force" -eq 0 ]; then
    echo "install.sh: core.hooksPath is already '$current'; add the hook there," >&2
    echo "  use --git-hooks, or rerun with --force to switch to .githooks" >&2
    exit 1
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
