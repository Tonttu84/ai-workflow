#!/usr/bin/env bash
# Copies a template from this ai-workflow clone into a project and
# records the copy, with the clone's commit, in the project's
# .ai-workflow-copies, so that scripts/check-drift.sh can tell a change
# to the template from the project's own edits (D153). It writes the
# record's other lines too: hooks/install.sh records its install with
# --record, and --notes-followed records the upgrade notes as followed,
# which nothing else does (D156).
#
# Usage: copy-template.sh [--force | --base <commit>] <template> <dest> [project-dir]
#        copy-template.sh --record [--force] [--dry-run] <project-dir> <path> <dest> [<path> <dest>...]
#        copy-template.sh --notes-followed [--force] [project-dir]
#
#   <template>   a file in this clone's templates/, such as
#                templates/commit-check.yml (or commit-check.yml)
#   <dest>       its path in the project, from the top of the repository,
#                such as .github/workflows/commit-check.yml: plain
#                characters (letters, digits, . _ @ + -), no . or ..
#                component, none starting with -
#   project-dir  any folder in the project's git repository (default .)
#   <commit>     a full commit SHA of this clone
#
# A <dest> that does not exist gets a plain copy. One that exists keeps
# the project's edits: the template's changes since the commit the record
# names for it, or since --base (the commit check-drift.sh guessed for a
# copy the record does not list), are merged into it with git merge-file;
# a copy with CRLF endings keeps them. A conflict leaves the markers in
# <dest>, changes no record and exits 1: resolve it, then --record it. An
# existing <dest> with neither is refused; --force replaces it with the
# template. The template must be committed in the clone, so that the
# commit recorded holds what was copied.
#
#   --record          records files already in the project as copies of
#                     <path> in this clone at its commit: what install.sh
#                     copied (.git/hooks/<name> stands for the clone's own
#                     hooks folder), or a copy brought up to date by hand
#   --notes-followed  records that the project has followed the upgrade
#                     notes (docs/upgrading.md) up to the clone's commit;
#                     check-drift.sh then lists only notes added after it
#   --dry-run         with --record: only checks that it could record,
#                     before hooks/install.sh copies anything
#
# It refuses to work from a clone older than the record (a commit the
# record names, or --base, that is not in the history of the clone's
# HEAD), which would take changes back out of a copy, and to rewrite a
# record with a line that is not valid. A record commit on no branch of
# the clone came from an ai-workflow branch that was squashed or rebased:
# compare the copy by hand, then --force (on a copy, --record or
# --notes-followed) records it at the clone's HEAD anyway (D168). The
# record, and a copied or merged <dest>, are staged (git update-index
# --add): commit them. The record names no path outside the project.
#
# Exit status: 0 done, 1 refused, a merge conflict or a git failure,
# 2 bad usage.
set -u

clone=$(cd "$(dirname "$0")/.." && pwd)
RECORD=.ai-workflow-copies
# What a record line may hold, as check-drift.sh reads it (D164).
SHA_RE='^([0-9a-f]{40}|[0-9a-f]{64})$'
PATH_RE='^[A-Za-z0-9._@+-]+(/[A-Za-z0-9._@+-]+)*$'
NOTES_LINE_RE='^notes ([^ ]+)$'
COPY_LINE_RE='^([^ ]+) ([^ ]+) ([^ ]+)$'

usage() {
  sed -n 's/^# Usage: /Usage: /p; s/^#        copy/       copy/p' "$0" >&2
  exit 2
}
die() { echo "copy-template.sh: $*" >&2; exit 1; }
bad() { echo "copy-template.sh: $*" >&2; exit 2; }

valid_sha() {
  local LC_ALL=C
  [[ $1 =~ $SHA_RE ]]
}
# valid_path <path>: relative, plain characters, no component that is
# . or .. or starts with -
valid_path() {
  local LC_ALL=C
  [[ $1 =~ $PATH_RE ]] || return 1
  case /$1/ in */./* | */../* | */-*) return 1 ;; esac
}
# valid_source <path>: a path in the clone the record may name
valid_source() {
  valid_path "$1" || return 1
  case $1 in hooks/* | scripts/* | templates/*) return 0 ;; esac
  return 1
}
# safe_dest <dest>: a path in the project a template may be copied to:
# not into .git, in any case (Windows takes .GIT for .git)
safe_dest() {
  local lower
  valid_path "$1" || return 1
  lower=$(printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]')
  case $lower in .git | .git/*) return 1 ;; esac
}

# project_top <dir>: the top of the git repository holding the folder
project_top() {
  git -C "$1" rev-parse --show-toplevel 2> /dev/null || bad "$1 is not in a git repository"
}
clone_head() {
  git -C "$clone" rev-parse -q --verify HEAD 2> /dev/null ||
    die "the ai-workflow clone at $clone is not a git repository"
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

# load_record <top>: $rec_notes and $rec_entries ("<commit> <path> <dest>"
# lines) from the record; refuses one with a line that is not valid
load_record() {
  local line n=0 bad='' c there here
  rec_notes='' rec_entries=''
  [ -f "$1/$RECORD" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line=${line%$'\r'}
    case $line in '' | '#'*) continue ;; esac
    if [[ $line =~ $NOTES_LINE_RE ]]; then
      c=${BASH_REMATCH[1]}
      if valid_sha "$c"; then
        rec_notes=$c
        continue
      fi
    elif [[ $line =~ $COPY_LINE_RE ]]; then
      c=${BASH_REMATCH[1]} there=${BASH_REMATCH[2]} here=${BASH_REMATCH[3]}
      if valid_sha "$c" && valid_source "$there" && valid_path "$here"; then
        rec_entries="$rec_entries$c $there $here"$'\n'
        continue
      fi
    fi
    bad="$bad${bad:+, }$n"
  done < "$1/$RECORD"
  [ -z "$bad" ] || die "line(s) $bad of $1/$RECORD are not valid: fix or delete them first (a record line is a full commit SHA and two plain relative paths, or \"notes\" and a full SHA)"
}
# recorded_commit <dest>: the commit the loaded record names for the copy
recorded_commit() {
  printf '%s' "$rec_entries" | DEST="$1" awk '$3 == ENVIRON["DEST"] { c = $1 } END { print c }'
}
# forward <commit> <what>: refuses unless the commit is in the history of
# the clone's HEAD, or --force says to record over it: working from a
# clone older than the record would take changes back out of a copy. A
# commit on no branch of the clone came from an ai-workflow branch that
# was squashed or rebased, which no pull brings back (D168).
forward() {
  local branches
  [ "$force" -eq 0 ] || return 0
  git -C "$clone" merge-base --is-ancestor --end-of-options "$1" HEAD 2> /dev/null
  case $? in
    0) return 0 ;;
    1) ;;
    *) die "$2 names ${1:0:7}, which the ai-workflow clone does not have: pull the clone. If it still lacks it, the record came from an ai-workflow branch that was squashed or rebased: compare the copy by hand, then rerun with --force" ;;
  esac
  branches=$(git -C "$clone" for-each-ref --format=x --contains="$1" refs/heads refs/remotes 2> /dev/null) ||
    die "could not check $2: git for-each-ref failed"
  [ -n "$branches" ] ||
    die "$2 names ${1:0:7}, which is on no branch of the ai-workflow clone: it came from a branch that was squashed or rebased. Compare the copy by hand, then rerun with --force"
  die "the ai-workflow clone is older than the record, or on another branch: $2 names ${1:0:7}, which is not in the history of its HEAD; pull the clone or check out its default branch"
}

# update_record <top> <notes commit or -> <commit> [<path> <dest>]...:
# writes the loaded record with these copies in place of any lines for
# the same paths, and the notes line (- keeps the one there), then
# stages it
update_record() {
  local top=$1 notes=$2 commit=$3 new='' tmp
  shift 3
  while [ "$#" -ge 2 ]; do
    new="$new$commit $1 $2"$'\n'
    shift 2
  done
  [ "$notes" != - ] || notes=$rec_notes
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
    [ -z "$notes" ] || printf 'notes %s\n' "$notes"
    # The new copies replace any lines for the same paths; then all by path.
    printf '%s' "$rec_entries" | NEW="$new" awk '
      BEGIN {
        n = split(ENVIRON["NEW"], lines, "\n")
        for (i = 1; i <= n; i++) if (split(lines[i], f, " ") == 3) entry[f[3]] = lines[i]
      }
      NF == 3 && !($3 in entry) { entry[$3] = $0 }
      END { for (d in entry) print entry[d] }
    ' | LC_ALL=C sort -t ' ' -k 3
  } > "$tmp" || { rm -f "$tmp"; die "cannot write $top/$RECORD"; }
  mv "$tmp" "$top/$RECORD" || { rm -f "$tmp"; die "cannot write $top/$RECORD"; }
  git -C "$top" update-index --add -- "$RECORD" || die "cannot stage $RECORD in $top"
}

# check_copy <top> <path> <dest>: a file of the clone, and a copy of it
# in the project (unless $dry_run), that --record may list, not over a
# line the clone is older than
check_copy() {
  local c
  valid_source "$2" || bad "not a path of hooks/, scripts/ or templates/ in the clone: $2"
  [ -f "$clone/$2" ] || die "$2 is not a file in the ai-workflow clone"
  case $3 in .git/hooks/?*) valid_path "$3" ;; *) safe_dest "$3" ;; esac || bad "not a plain path inside the project: $3"
  [ "$dry_run" -eq 1 ] || [ -f "$(where "$1" "$3")" ] || die "$3 is not in the project; copy it first"
  c=$(recorded_commit "$3")
  [ -z "$c" ] || forward "$c" "the record's line for $3"
}

# record_files [--force] [--dry-run] <project-dir> <path> <dest>...: --record
record_files() {
  local top head pairs
  while :; do
    case ${1-} in
      --force) force=1 ;;
      --dry-run) dry_run=1 ;;
      *) break ;;
    esac
    shift
  done
  [ "$#" -ge 3 ] && [ $(($# % 2)) -eq 1 ] || usage
  top=$(project_top "$1") || exit 2
  shift
  head=$(clone_head) || exit 1
  load_record "$top"
  pairs=("$@")
  while [ "$#" -ge 2 ]; do
    check_copy "$top" "$1" "$2"
    shift 2
  done
  [ "$dry_run" -eq 0 ] || return 0
  update_record "$top" - "$head" "${pairs[@]}"
  echo "Recorded $((${#pairs[@]} / 2)) file(s) at ${head:0:7} in $top/$RECORD and staged it. Commit it."
}

# notes_followed [--force] [project-dir]: --notes-followed
notes_followed() {
  local top head
  if [ "${1-}" = --force ]; then
    force=1
    shift
  fi
  [ "$#" -le 1 ] || usage
  top=$(project_top "${1:-.}") || exit 2
  head=$(clone_head) || exit 1
  load_record "$top"
  [ -z "$rec_notes" ] || forward "$rec_notes" "the record's notes line"
  update_record "$top" "$head" "$head"
  echo "Recorded in $top/$RECORD that the upgrade notes are followed up to ${head:0:7}, and staged it. Commit it."
}

# merge_into <target> <template> <base> <head> <dest>: the template's
# change from base to head, merged into the copy with git merge-file. A
# copy checked out with CRLF endings (core.autocrlf=true) is merged
# without them and gets them back: else every line would conflict.
merge_into() {
  local target=$1 t=$2 base=$3 head=$4 dest=$5 old cur status crlf=0
  old=$(mktemp) || die "cannot make a scratch file"
  cur=$(mktemp) || { rm -f "$old"; die "cannot make a scratch file"; }
  if ! git -C "$clone" show --end-of-options "$base:$t" > "$old" 2> /dev/null; then
    rm -f "$old" "$cur"
    die "$t did not exist at ${base:0:7}; use --force to replace $dest"
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
  local t=$1 dest=$2 top head target base recorded what
  [ "$#" -le 3 ] || usage
  case $t in templates/*) ;; */*) bad "not a template: $t" ;; *) t=templates/$t ;; esac
  valid_source "$t" || bad "not a template: $t"
  [ -f "$clone/$t" ] || die "$t is not a file in the ai-workflow clone"
  safe_dest "$dest" || bad "not a plain path inside the project: $dest"
  top=$(project_top "${3:-.}") || exit 2
  head=$(clone_head) || exit 1
  if ! git -C "$clone" ls-files --error-unmatch -- "$t" > /dev/null 2>&1 ||
    ! git -C "$clone" diff --quiet HEAD -- "$t"; then
    die "$t has changes the ai-workflow clone has not committed; commit or drop them first"
  fi
  load_record "$top"
  recorded=$(recorded_commit "$dest")
  [ -z "$recorded" ] || forward "$recorded" "the record's line for $dest"
  target="$top/$dest"
  if [ ! -e "$target" ] || [ "$force" -eq 1 ]; then
    { mkdir -p "$(dirname "$target")" && cp "$clone/$t" "$target"; } || die "cannot write $target"
    what="Copied $t to"
  elif tr -d '\r' < "$target" | cmp -s "$clone/$t" -; then
    what="$t is already in" # the same lines, CRLF endings or not
  else
    base=${base_opt:-$recorded}
    [ -n "$base" ] || die "$dest exists, and $RECORD names no commit it came from: pass --base <commit> (check-drift.sh names the closest version) or --force to replace it"
    forward "$base" "the base for $dest"
    merge_into "$target" "$t" "$base" "$head" "$dest"
    what="Merged the changes to $t since ${base:0:7} into"
  fi
  update_record "$top" - "$head" "$t" "$dest"
  git -C "$top" update-index --add -- "$dest" || die "cannot stage $dest in $top"
  echo "$what $top/$dest, recorded it at ${head:0:7} in $RECORD and staged both. Commit them."
}

force=0
dry_run=0
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
      valid_sha "$2" || bad "--base takes a full commit SHA of the clone"
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
