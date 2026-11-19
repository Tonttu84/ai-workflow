#!/usr/bin/env bash
# Copies a template from this ai-workflow clone into a project and
# records the copy, with the clone's commit, in the project's
# .ai-workflow-copies, so that scripts/check-drift.sh can tell a change
# to the template from the project's own edits (D153). It writes the
# record's other lines too: hooks/install.sh records its install with
# --record, and --notes-followed records the upgrade notes as followed.
#
# Usage: copy-template.sh [--force | --base <commit>] <template> <dest> [project-dir]
#        copy-template.sh --record <project-dir> <path> <dest> [<path> <dest>...]
#        copy-template.sh --notes-followed [project-dir]
#
#   <template>   a file in this clone's templates/, such as
#                templates/commit-check.yml (or commit-check.yml)
#   <dest>       its path in the project, from the top of the repository,
#                such as .github/workflows/commit-check.yml
#   project-dir  any folder in the project's git repository (default .)
#
# A <dest> that does not exist gets a plain copy. One that exists keeps
# the project's edits: the template's changes since the commit the record
# names for it, or since --base (the commit check-drift.sh guessed for a
# copy the record does not list), are merged into it with git merge-file.
# A conflict leaves the markers in <dest>, changes no record and exits 1:
# resolve it, then --record it. An existing <dest> with neither is
# refused; --force replaces it with the template. The template must be
# committed in the clone, so that the commit recorded holds what was
# copied.
#
#   --record          records files already in the project as copies of
#                     <path> in this clone at its commit: what install.sh
#                     copied (.git/hooks/<name> stands for the clone's own
#                     hooks folder), or a copy brought up to date by hand
#   --notes-followed  records that the project has followed the upgrade
#                     notes (docs/upgrading.md) up to the clone's commit;
#                     check-drift.sh then lists only notes added after it
#
# The record, and a copied or merged <dest>, are staged (git update-index
# --add): commit them. The record names no path outside the project.
#
# Exit status: 0 done, 1 refused, a merge conflict or a git failure,
# 2 bad usage.
set -u

clone=$(cd "$(dirname "$0")/.." && pwd)
RECORD=.ai-workflow-copies
TAB=$(printf '\t')

usage() {
  sed -n 's/^# Usage: /Usage: /p; s/^#        copy/       copy/p' "$0" >&2
  exit 2
}
die() { echo "copy-template.sh: $*" >&2; exit 1; }
bad() { echo "copy-template.sh: $*" >&2; exit 2; }

# project_top <dir>: the top of the git repository holding the folder
project_top() {
  git -C "$1" rev-parse --show-toplevel 2> /dev/null || bad "$1 is not in a git repository"
}
clone_head() {
  git -C "$clone" rev-parse -q --verify HEAD 2> /dev/null ||
    die "the ai-workflow clone at $clone is not a git repository"
}
# safe_dest <dest>: a relative path inside the project, outside .git/
safe_dest() {
  case $1 in
    '' | /* | [A-Za-z]:* | *\\* | .git | .git/* | *$'\n'* | *"$TAB"*) return 1 ;;
  esac
  case /$1/ in */../* | */./*) return 1 ;; esac
}
# where <top> <dest>: the file a path in the record stands for
where() {
  local hooks
  case $2 in
    .git/hooks/*)
      hooks=$(git -C "$1" rev-parse --git-path hooks) || return 1
      case $hooks in /* | [A-Za-z]:*) ;; *) hooks="$1/$hooks" ;; esac
      printf '%s/%s\n' "$hooks" "${2#.git/hooks/}" ;;
    *) printf '%s/%s\n' "$1" "$2" ;;
  esac
}
# recorded_commit <top> <dest>: the commit the record names for the copy
recorded_commit() {
  [ -f "$1/$RECORD" ] || return 0
  DEST="$2" awk '
    { sub(/\r$/, "") }
    /^#/ || NF < 3 || $1 == "notes" { next }
    { d = $0; sub(/^[^ ]+ [^ ]+ /, "", d); if (d == ENVIRON["DEST"]) c = $1 }
    END { print c }
  ' "$1/$RECORD"
}

# update_record <top> <notes commit or -> <commit> [<path> <dest>]...:
# writes the record with these copies in place of any lines for the same
# paths, and the notes line (- keeps the one there), then stages it
update_record() {
  local top=$1 notes=$2 commit=$3 new='' tmp
  shift 3
  while [ "$#" -ge 2 ]; do
    new="$new$commit $1 $2"$'\n'
    shift 2
  done
  tmp=$(mktemp "$top/$RECORD.XXXXXX") || die "cannot write in $top"
  {
    printf '%s\n' \
      '# The files this project copied from ai-workflow' \
      '# (https://github.com/Tonttu84/ai-workflow), each with the commit of the' \
      '# ai-workflow clone it came from: <commit> <path there> <path here>.' \
      '# "notes <commit>": the project has followed the upgrade notes' \
      '# (docs/upgrading.md there) up to that commit. hooks/install.sh and' \
      '# scripts/copy-template.sh there write this file, and' \
      '# scripts/check-drift.sh reads it; do not edit it by hand.'
    { [ -f "$top/$RECORD" ] && cat "$top/$RECORD"; } | NOTES="$notes" NEW="$new" awk '
      function dest(line) { sub(/^[^ ]+ [^ ]+ /, "", line); return line }
      BEGIN {
        n = split(ENVIRON["NEW"], lines, "\n")
        for (i = 1; i <= n; i++) if (lines[i] != "") entry[dest(lines[i])] = lines[i]
      }
      { sub(/\r$/, "") }
      /^#/ || NF == 0 { next }
      $1 == "notes" { old = $0; next }
      NF >= 3 { d = dest($0); if (!(d in entry)) entry[d] = $0 }
      END {
        # A sort key ahead of each line: the notes line first, then the
        # copies by their path in the project.
        if (ENVIRON["NOTES"] != "-") print "0\t\tnotes " ENVIRON["NOTES"]
        else if (old != "") print "0\t\t" old
        for (d in entry) print "1\t" d "\t" entry[d]
      }
    ' | LC_ALL=C sort -t "$TAB" -k 1,1 -k 2,2 | cut -f 3-
  } > "$tmp" || { rm -f "$tmp"; die "cannot write $top/$RECORD"; }
  mv "$tmp" "$top/$RECORD" || { rm -f "$tmp"; die "cannot write $top/$RECORD"; }
  git -C "$top" update-index --add -- "$RECORD" || die "cannot stage $RECORD in $top"
}

# check_copy <top> <path> <dest>: a file of the clone, and a copy of it
# in the project, that --record may list
check_copy() {
  case $2 in '' | /* | *..* | *[[:space:]]*) bad "not a path in the clone: $2" ;; esac
  [ -f "$clone/$2" ] || die "$2 is not a file in the ai-workflow clone"
  case $3 in .git/hooks/?*) ;; *) safe_dest "$3" || bad "not a path inside the project: $3" ;; esac
  [ -f "$(where "$1" "$3")" ] || die "$3 is not in the project; copy it first"
}

# record_files <project-dir> <path> <dest>...: --record
record_files() {
  local top head pairs
  [ "$#" -ge 3 ] && [ $(($# % 2)) -eq 1 ] || usage
  top=$(project_top "$1") || exit 2
  shift
  head=$(clone_head) || exit 1
  pairs=("$@")
  while [ "$#" -ge 2 ]; do
    check_copy "$top" "$1" "$2"
    shift 2
  done
  update_record "$top" - "$head" "${pairs[@]}"
  echo "Recorded $((${#pairs[@]} / 2)) file(s) at ${head:0:7} in $top/$RECORD and staged it. Commit it."
}

# notes_followed [project-dir]: --notes-followed
notes_followed() {
  local top head
  [ "$#" -le 1 ] || usage
  top=$(project_top "${1:-.}") || exit 2
  head=$(clone_head) || exit 1
  update_record "$top" "$head" "$head"
  echo "Recorded in $top/$RECORD that the upgrade notes are followed up to ${head:0:7}, and staged it. Commit it."
}

# merge_into <target> <template> <base> <head> <dest>: the template's
# change from base to head, merged into the copy with git merge-file. A
# copy checked out with CRLF endings (core.autocrlf=true) is merged
# without them and gets them back: else every line would conflict.
merge_into() {
  local target=$1 t=$2 base=$3 head=$4 dest=$5 old cur status crlf=0
  git -C "$clone" cat-file -e "$base^{commit}" 2> /dev/null || die "commit $base is not in the ai-workflow clone"
  old=$(mktemp) && cur=$(mktemp) || die "cannot make a scratch file"
  if ! git -C "$clone" show "$base:$t" > "$old" 2> /dev/null; then
    rm -f "$old" "$cur"
    die "$t did not exist at $base; use --force to replace $dest"
  fi
  tr -d '\r' < "$target" > "$cur"
  [ "$(wc -c < "$cur")" -eq "$(wc -c < "$target")" ] || crlf=1
  git merge-file -L "$dest" -L "$t at ${base:0:7}" -L "$t at ${head:0:7}" "$cur" "$old" "$clone/$t"
  status=$?
  if [ "$status" -lt 128 ]; then
    if [ "$crlf" -eq 1 ]; then awk '{ print $0 "\r" }' "$cur" > "$target"; else cat "$cur" > "$target"; fi
  fi
  rm -f "$old" "$cur"
  [ "$status" -eq 0 ] && return 0
  if [ "$status" -gt 0 ] && [ "$status" -lt 128 ]; then
    echo "copy-template.sh: $status conflict(s) merging $t into $dest; the markers are in it." >&2
    echo "  Resolve them, then record the copy: bash $0 --record <project-dir> $t $dest" >&2
  fi
  exit 1
}

# copy_template <template> <dest> [project-dir]: the main form
copy_template() {
  local t=$1 dest=$2 top head target base what
  [ "$#" -le 3 ] || usage
  case $t in templates/*) ;; */*) bad "not a template: $t" ;; *) t=templates/$t ;; esac
  case $t in *..* | *[[:space:]]*) bad "not a template: $t" ;; esac
  [ -f "$clone/$t" ] || die "$t is not a file in the ai-workflow clone"
  safe_dest "$dest" || bad "not a path inside the project: $dest"
  top=$(project_top "${3:-.}") || exit 2
  head=$(clone_head) || exit 1
  if ! git -C "$clone" ls-files --error-unmatch -- "$t" > /dev/null 2>&1 ||
    ! git -C "$clone" diff --quiet HEAD -- "$t"; then
    die "$t has changes the ai-workflow clone has not committed; commit or drop them first"
  fi
  target="$top/$dest"
  if [ ! -e "$target" ] || [ "$force" -eq 1 ]; then
    { mkdir -p "$(dirname "$target")" && cp "$clone/$t" "$target"; } || die "cannot write $target"
    what="Copied $t to"
  elif tr -d '\r' < "$target" | cmp -s "$clone/$t" -; then
    what="$t is already in" # the same lines, CRLF endings or not
  else
    base=${base_opt:-$(recorded_commit "$top" "$dest")}
    [ -n "$base" ] || die "$dest exists, and $RECORD names no commit it came from: pass --base <commit> (check-drift.sh names the closest version) or --force to replace it"
    merge_into "$target" "$t" "$base" "$head" "$dest"
    what="Merged the changes to $t since ${base:0:7} into"
  fi
  update_record "$top" - "$head" "$t" "$dest"
  git -C "$top" update-index --add -- "$dest" || die "cannot stage $dest in $top"
  echo "$what $top/$dest, recorded it at ${head:0:7} in $RECORD and staged both. Commit them."
}

force=0
base_opt=
case ${1-} in
  -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
  --record) shift; record_files "$@"; exit 0 ;;
  --notes-followed) shift; notes_followed "$@"; exit 0 ;;
esac
while [ $# -gt 0 ]; do
  case $1 in
    --force) force=1 ;;
    --base)
      [ $# -ge 2 ] || usage
      base_opt=$2
      shift ;;
    -*) usage ;;
    *) break ;;
  esac
  shift
done
[ "$force" -eq 0 ] || [ -z "$base_opt" ] || bad "--force and --base exclude each other"
[ $# -ge 2 ] || usage
copy_template "$@"
