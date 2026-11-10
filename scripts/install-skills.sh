#!/usr/bin/env bash
# Copies the skills in skills/ to the user-level Claude Code skills
# directory, replacing older copies of the same skills.
#
# Usage: install-skills.sh [target-dir]
#   target-dir defaults to $CLAUDE_CONFIG_DIR/skills, else ~/.claude/skills
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
target=${1:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills}
[ -n "$target" ] || { echo "install-skills.sh: empty target" >&2; exit 1; }
mkdir -p "$target"

for dir in "$ROOT"/skills/*/; do
  dir=${dir%/}
  [ -f "$dir/SKILL.md" ] || continue
  name=$(basename "$dir")
  rm -rf "${target:?}/$name"
  cp -R "$dir" "$target/$name"
  echo "Installed $name -> $target/$name"
done
