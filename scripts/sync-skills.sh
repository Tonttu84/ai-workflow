#!/usr/bin/env bash
# Fetches the latest upstream grill skills into skills/ and re-applies
# the local overlays from skills/overlays/<name>/.
#
# Usage: sync-skills.sh [--ref <branch|tag|commit>] [--from <dir>] [--dest <dir>]
#
#   --ref   upstream ref to fetch (default: main)
#   --from  use an existing local checkout of the upstream repo instead
#           of fetching (no network; used by the tests)
#   --dest  where to write the skills (default: skills/ in this repo)
#
# Review the result with `git diff skills/` before committing it.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO=https://github.com/mattpocock/skills
SKILLS="grilling grill-me"

ref=main
from=
dest="$ROOT/skills"
while [ $# -gt 0 ]; do
  case $1 in
    --ref) ref=${2:?--ref needs a value}; shift ;;
    --from) from=${2:?--from needs a value}; shift ;;
    --dest) dest=${2:?--dest needs a value}; shift ;;
    -h | --help) sed -n '2,13p' "$0"; exit 0 ;;
    *) echo "sync-skills.sh: unknown argument $1" >&2; exit 2 ;;
  esac
  shift
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -z "$from" ]; then
  echo "Fetching $REPO at $ref"
  git init -q "$tmp/upstream"
  git -C "$tmp/upstream" fetch -q --depth 1 "$REPO.git" "$ref"
  git -C "$tmp/upstream" -c core.autocrlf=false checkout -q FETCH_HEAD
  from="$tmp/upstream"
fi
commit=$(git -C "$from" rev-parse HEAD 2> /dev/null || echo unknown)

# Stage every skill first, so a missing one leaves dest untouched.
for name in $SKILLS; do
  matches=$(find "$from/skills" -type d -name "$name" \
    -not -path '*/deprecated/*' -not -path '*/in-progress/*')
  count=$(printf '%s' "$matches" | grep -c . || true)
  if [ "$count" -ne 1 ] || [ ! -f "$matches/SKILL.md" ]; then
    echo "sync-skills.sh: expected one '$name' skill upstream, found $count" >&2
    exit 1
  fi
  cp -R "$matches" "$tmp/stage-$name"
  if [ -d "$ROOT/skills/overlays/$name" ]; then
    bash "$ROOT/scripts/apply-skill-overlay.sh" "$tmp/stage-$name" "$ROOT/skills/overlays/$name"
  fi
done

mkdir -p "$dest"
for name in $SKILLS; do
  rm -rf "${dest:?}/$name"
  cp -R "$tmp/stage-$name" "$dest/$name"
done
cp "$from/LICENSE" "$dest/LICENSE"
cat > "$dest/UPSTREAM" << EOF
repo: $REPO
ref: $ref
commit: $commit
synced: $(date -u +%Y-%m-%d)
skills: $SKILLS
EOF

echo "Synced $SKILLS from $REPO at $commit into $dest"
