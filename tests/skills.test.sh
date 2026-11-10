#!/usr/bin/env bash
# Tests for the skill scripts, all offline: a fake upstream checkout
# stands in for mattpocock/skills.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

APPLY="$ROOT/scripts/apply-skill-overlay.sh"
SYNC="$ROOT/scripts/sync-skills.sh"
INSTALL="$ROOT/scripts/install-skills.sh"
quiet() { "$@" > /dev/null 2>&1; }

write_skill() { # write_skill <file> <description>
  mkdir -p "$(dirname "$1")"
  printf -- '---\nname: grilling\ndescription: %s\n---\n\nInterview the user.\n' "$2" > "$1"
}

# --- apply-skill-overlay.sh
mkdir -p "$TMP/s1"
write_skill "$TMP/s1/SKILL.md" "Grill the user."
check "overlay applies" quiet bash "$APPLY" "$TMP/s1" "$ROOT/skills/overlays/grilling"
suffix=$(cat "$ROOT/skills/overlays/grilling/description-suffix.txt")
check "description gets the suffix" grep -qxF "description: Grill the user. $suffix" "$TMP/s1/SKILL.md"
check "frontmatter still closes" test "$(grep -c '^---$' "$TMP/s1/SKILL.md")" -eq 2
check "body keeps upstream text" grep -qxF "Interview the user." "$TMP/s1/SKILL.md"
check "override section appended" grep -qxF "## Local override (ai-workflow)" "$TMP/s1/SKILL.md"
cp "$TMP/s1/SKILL.md" "$TMP/s1.once"
check "second apply succeeds" quiet bash "$APPLY" "$TMP/s1" "$ROOT/skills/overlays/grilling"
check "applying twice changes nothing" cmp -s "$TMP/s1.once" "$TMP/s1/SKILL.md"

mkdir -p "$TMP/s2" "$TMP/bad-overlay"
write_skill "$TMP/s2/SKILL.md" "Grill the user."
printf 'Use it when: always\n' > "$TMP/bad-overlay/description-suffix.txt"
refute "suffix containing ': ' is refused (breaks YAML)" quiet bash "$APPLY" "$TMP/s2" "$TMP/bad-overlay"

mkdir -p "$TMP/s3"
printf -- '---\nname: grilling\n---\n\nBody.\n' > "$TMP/s3/SKILL.md"
refute "skill without a description is refused" quiet bash "$APPLY" "$TMP/s3" "$ROOT/skills/overlays/grilling"

overlay_is_applied() {
  cp -r "$ROOT/skills/grilling" "$TMP/vendored" &&
    quiet bash "$APPLY" "$TMP/vendored" "$ROOT/skills/overlays/grilling" &&
    cmp -s "$ROOT/skills/grilling/SKILL.md" "$TMP/vendored/SKILL.md"
}
check "vendored grilling skill already carries the overlay" overlay_is_applied

# --- sync-skills.sh --from <local checkout>
up="$TMP/upstream"
write_skill "$up/skills/productivity/grilling/SKILL.md" "Grill the user."
mkdir -p "$up/skills/productivity/grilling/agents" "$up/skills/productivity/grill-me"
printf 'interface:\n  display_name: "Grilling"\n' > "$up/skills/productivity/grilling/agents/openai.yaml"
printf -- '---\nname: grill-me\ndescription: Interview.\n---\n\nRun grilling.\n' > "$up/skills/productivity/grill-me/SKILL.md"
printf 'MIT License\n\nCopyright (c) Upstream\n' > "$up/LICENSE"
git init -q -b main "$up"
git -C "$up" -c core.autocrlf=false add -A
git -C "$up" -c user.name=t -c user.email=t@example.com commit -q -m "chore: fake upstream"
sha=$(git -C "$up" rev-parse HEAD)

out="$TMP/out"
mkdir -p "$out/grilling"
printf 'stale\n' > "$out/grilling/stale.md"
check "sync from a local checkout succeeds" quiet bash "$SYNC" --from "$up" --dest "$out"
check "grilling synced with the overlay" grep -qxF "description: Grill the user. $suffix" "$out/grilling/SKILL.md"
check "grilling agents file synced" test -f "$out/grilling/agents/openai.yaml"
check "grill-me synced unchanged" cmp -s "$up/skills/productivity/grill-me/SKILL.md" "$out/grill-me/SKILL.md"
check "stale files removed" test ! -e "$out/grilling/stale.md"
check "upstream licence copied" cmp -s "$up/LICENSE" "$out/LICENSE"
check "upstream commit recorded" grep -qxF "commit: $sha" "$out/UPSTREAM"

check "sync --help prints the comment block and no code" help_ok "$SYNC"

# A failed sync leaves dest exactly as it was.
cp -R "$out" "$TMP/out.before"
unchanged() { diff -r "$TMP/out.before" "$out" > /dev/null; }
printf -- '---\nname: grill-me\ndescription: Newer.\n---\n\nRun grilling.\n' > "$up/skills/productivity/grill-me/SKILL.md"
mv "$up/LICENSE" "$TMP/LICENSE.up"
refute "sync fails when upstream has no LICENSE" quiet bash "$SYNC" --from "$up" --dest "$out"
check "a missing LICENSE leaves dest untouched" unchanged
mv "$TMP/LICENSE.up" "$up/LICENSE"

rm -rf "$up/skills/productivity/grill-me"
refute "sync fails when a skill is missing upstream" quiet bash "$SYNC" --from "$up" --dest "$out"
check "a missing skill leaves dest untouched" unchanged

# --- install-skills.sh <target>
target="$TMP/home-skills"
mkdir -p "$target/grilling"
printf 'old\n' > "$target/grilling/old.md"
check "install succeeds" quiet bash "$INSTALL" "$target"
check "grilling installed" cmp -s "$ROOT/skills/grilling/SKILL.md" "$target/grilling/SKILL.md"
check "grill-me installed" cmp -s "$ROOT/skills/grill-me/SKILL.md" "$target/grill-me/SKILL.md"
check "old copy replaced, not merged" test ! -e "$target/grilling/old.md"
check "overlays not installed as a skill" test ! -e "$target/overlays"

finish
