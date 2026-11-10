#!/usr/bin/env bash
# Re-applies a local overlay to a skill copied from upstream.
#
# Usage: apply-skill-overlay.sh <skill-dir> <overlay-dir>
#
# An overlay directory may hold:
#   description-suffix.txt  one line appended to the SKILL.md description
#   append.md               a section appended to the end of SKILL.md
# Both steps are idempotent: running the script twice changes nothing.
set -eu

skill=${1:?usage: apply-skill-overlay.sh <skill-dir> <overlay-dir>}
overlay=${2:?usage: apply-skill-overlay.sh <skill-dir> <overlay-dir>}
file="$skill/SKILL.md"
die() { echo "apply-skill-overlay.sh: $*" >&2; exit 1; }
[ -f "$file" ] || die "$file not found"

if [ -f "$overlay/description-suffix.txt" ]; then
  suffix=$(tr -d '\r' < "$overlay/description-suffix.txt")
  case $suffix in
    *$'\n'*) die "description-suffix.txt must be one line" ;;
    *': '* | *' #'*) die "description-suffix.txt must not contain ': ' or ' #' (breaks YAML)" ;;
  esac
  if ! grep -qF -- "$suffix" "$file"; then
    SUFFIX=$suffix awk '
      BEGIN { fm = 0; done = 0 }
      /^---$/ { fm++ }
      fm == 1 && !done && /^description: / {
        value = substr($0, 14)
        if (value ~ /^["'"'"'>|]/) { bad = 1 }
        else { $0 = $0 " " ENVIRON["SUFFIX"]; done = 1 }
      }
      { print }
      END { if (bad) exit 3; if (!done) exit 2 }
    ' "$file" > "$file.tmp" || {
      status=$?
      rm -f "$file.tmp"
      [ "$status" -eq 3 ] && die "$file: description is quoted or multi-line; update this script"
      die "$file: no 'description:' line in the frontmatter"
    }
    mv "$file.tmp" "$file"
  fi
fi

if [ -f "$overlay/append.md" ]; then
  heading=$(head -n 1 "$overlay/append.md" | tr -d '\r')
  if ! grep -qxF -- "$heading" "$file"; then
    [ -z "$(tail -c 1 "$file")" ] || printf '\n' >> "$file"
    printf '\n' >> "$file"
    cat "$overlay/append.md" >> "$file"
  fi
fi
