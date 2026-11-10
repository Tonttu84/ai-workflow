#!/usr/bin/env bash
# Re-applies a local overlay to a skill copied from upstream.
#
# Usage: apply-skill-overlay.sh <skill-dir> <overlay-dir>
#
# An overlay directory may hold:
#   description-suffix.txt  one line appended to the SKILL.md description
#   append.md               a section appended to the end of SKILL.md
#   replace.txt             exact-text replacements in any file of the
#                           skill, as records of three lines:
#                             file: <path inside the skill>
#                             old: <text upstream has>
#                             new: <text to put in its place>
#                           It fails when neither text is found, so an
#                           upstream rewording is noticed, not skipped.
# Every step is idempotent: running the script twice changes nothing.
# Overlay files may have CRLF line endings.
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
    tr -d '\r' < "$overlay/append.md" >> "$file"
  fi
fi

# replace_text <path inside the skill> <old> <new>
replace_text() {
  case /$1/ in
    *'/../'* | //*) die "replace.txt: '$1' is not a path inside the skill" ;;
  esac
  local target="$skill/$1"
  [ -f "$target" ] || die "replace.txt: $target not found"
  [ -n "$2" ] || die "replace.txt: empty 'old:' for $1"
  case $3 in *"$2"*) die "replace.txt: the new text for $1 contains the old text" ;; esac
  if grep -qF -- "$2" "$target"; then
    # Write back through cat, not mv, so the target keeps its mode.
    if ! OLD=$2 NEW=$3 awk '{
      out = ""; s = $0
      while ((i = index(s, ENVIRON["OLD"])) > 0) {
        out = out substr(s, 1, i - 1) ENVIRON["NEW"]
        s = substr(s, i + length(ENVIRON["OLD"]))
      }
      print out s
    }' "$target" > "$target.tmp"; then
      rm -f "$target.tmp"
      die "replace.txt: could not rewrite $target"
    fi
    cat "$target.tmp" > "$target"
    rm -f "$target.tmp"
  elif ! grep -qF -- "$3" "$target"; then
    die "replace.txt: '$2' not found in $target; upstream changed, update the overlay"
  fi
}

if [ -f "$overlay/replace.txt" ]; then
  path='' old='' new=''
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line%$'\r'}
    case $line in
      'file: '*) path=${line#file: } ;;
      'old: '*) old=${line#old: } ;;
      'new: '*)
        new=${line#new: }
        [ -n "$path" ] || die "replace.txt: 'new:' without a 'file:' line"
        replace_text "$path" "$old" "$new"
        old='' ;;
      '' | '#'*) ;;
      *) die "replace.txt: unexpected line: $line" ;;
    esac
  done < "$overlay/replace.txt"
fi
