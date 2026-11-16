#!/usr/bin/env bash
# Checks that locked tests are unchanged: every listed file, or every file
# under a listed directory, must be the same in the working tree and in the
# index as in the base commit (usually the test writer's test: commit).
#
# Usage: check-locked-tests.sh <base-sha> <path>...
#
# Paths are relative to the current directory, as in git. A change counts
# whether it was committed or not; so do a deleted file and a new file
# under a listed directory (untracked ones too, unless git ignores them).
# A change that was later put back does not count.
#
# Exit status: 0 nothing changed, 1 something changed (each file is named
# on stderr), 2 bad arguments.
set -eu

usage() { echo "Usage: check-locked-tests.sh <base-sha> <path>..." >&2; exit 2; }
die() { echo "check-locked-tests.sh: $*" >&2; exit 2; }
case ${1:-} in
  -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
esac
[ "$#" -ge 2 ] || usage

# Paths are literal, never globs, and non-ASCII names print as they are.
git() { command git --literal-pathspecs -c core.quotePath=false "$@"; }

git rev-parse --is-inside-work-tree > /dev/null 2>&1 || die "not inside a git work tree"
base=$(git rev-parse --verify --quiet "$1^{commit}") || die "unknown commit: $1"
shift
for path in "$@"; do
  [ -n "$path" ] || die "empty path"
  [ -n "$(git ls-tree -r --name-only "$base" -- "$path")" ] || die "not in $base: $path"
done

# "<status><TAB><path from the top of the repo>" lines: the working tree,
# then the index, then untracked files; a path is reported once.
worktree=$(git diff --name-status --no-renames "$base" -- "$@") || die "git diff failed"
index=$(git diff --cached --name-status --no-renames "$base" -- "$@") || die "git diff --cached failed"
untracked=$(git ls-files --others --exclude-standard --full-name -- "$@") || die "git ls-files failed"
changes=$(
  {
    printf '%s\n%s\n' "$worktree" "$index"
    printf '%s\n' "$untracked" | awk 'NF { print "A\t" $0 }'
  } | awk -F '\t' 'NF && !seen[$2]++'
)
[ -n "$changes" ] || exit 0

printf '%s\n' "$changes" | awk -F '\t' -v base="$base" '
  BEGIN { print "check-locked-tests.sh: locked tests differ from " base ":" }
  { word = $1 == "D" ? "deleted" : $1 == "A" ? "added" : "changed"; print "  " word ": " $2 }
' >&2
exit 1
