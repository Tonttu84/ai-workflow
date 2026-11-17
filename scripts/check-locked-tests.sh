#!/usr/bin/env bash
# Checks that locked tests are unchanged: every listed file, or every file
# under a listed directory, must be the same in HEAD (the commit that gets
# pushed), in the index and in the working tree as in the base commit
# (usually the test writer's test: commit).
#
# Usage: check-locked-tests.sh <base-sha> <path>...
#
# Paths are relative to the current directory, as in git. A change counts
# wherever it is: committed in HEAD, staged, or only in the working tree;
# so do a deleted file and a new file under a listed directory, untracked
# ones too. Only the project's committed .gitignore files may hide a new
# file: the clone's .git/info/exclude and a global excludes file reach no
# other clone, so a file only they hide counts, and an untracked
# .gitignore in or above a locked path fails, ignored or not (one that
# ignores itself hides what is next to it). A locked file that git was
# told not to look at (git update-index --skip-worktree or
# --assume-unchanged) fails, changed or not, since the flag hides changes.
# A change that was later put back, in a commit, does not count.
#
# Exit status: 0 nothing changed, 1 something changed (each file is named
# on stderr, with where it changed), 2 bad arguments.
set -eu

usage() { echo "Usage: check-locked-tests.sh <base-sha> <path>..." >&2; exit 2; }
die() { echo "check-locked-tests.sh: $*" >&2; exit 2; }
case ${1:-} in
  -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
esac
[ "$#" -ge 2 ] || usage

# Paths are literal, never globs, and non-ASCII names print as they are.
git() { command git --literal-pathspecs -c core.quotePath=false "$@"; }

# untracked_ignores <path>...: the untracked .gitignore files, ignored or
# not, in or above the paths, from the top of the repository, one per
# line. One that ignores itself hides the files next to it from git, and
# no other clone has it. The name is matched in any case: git on a
# case-insensitive file system (Windows, macOS) reads .GITIGNORE too.
untracked_ignores() {
  local path dir rel out icase=':(icase,literal)' specs=()
  for path in "$@"; do
    if [ -d "$path" ]; then dir=$path; else dir=$(dirname -- "$path"); fi
    while [ ! -d "$dir" ]; do dir=$(dirname -- "$dir"); done
    rel=$(cd -- "$dir" && command git rev-parse --show-prefix) || return 1
    if [ -d "$path" ]; then specs+=("$icase${rel:-.}"); fi
    while :; do
      specs+=("$icase${rel}.gitignore")
      [ -n "$rel" ] || break
      rel=${rel%/}
      case $rel in */*) rel=${rel%/*}/ ;; *) rel= ;; esac
    done
  done
  # Pathspec magic, so not the git() above (--literal-pathspecs), and
  # with the environment's global pathspec settings off.
  out=$(
    GIT_LITERAL_PATHSPECS=0 GIT_GLOB_PATHSPECS=0 GIT_NOGLOB_PATHSPECS=0 GIT_ICASE_PATHSPECS=0 \
      command git -C "$(git rev-parse --show-toplevel)" ls-files -z --others -- "${specs[@]}" | tr '\0' '\n'
    exit "${PIPESTATUS[0]}"
  ) || return 1
  printf '%s\n' "$out" | awk -F / 'tolower($NF) == ".gitignore"'
}

git rev-parse --is-inside-work-tree > /dev/null 2>&1 || die "not inside a git work tree"
base=$(git rev-parse --verify --quiet "$1^{commit}") || die "unknown commit: $1"
shift
for path in "$@"; do
  [ -n "$path" ] || die "empty path"
  [ -n "$(git ls-tree -r --name-only "$base" -- "$path")" ] || die "not in $base: $path"
done

# "<kind><TAB><path from the top of the repo><TAB><where>" lines.
committed=$(git diff --name-status --no-renames "$base" HEAD -- "$@") || die "git diff HEAD failed"
index=$(git diff --cached --name-status --no-renames "$base" -- "$@") || die "git diff --cached failed"
worktree=$(git diff --name-status --no-renames "$base" -- "$@") || die "git diff failed"
untracked=$(git ls-files --others --exclude-per-directory=.gitignore --full-name -- "$@") ||
  die "git ls-files failed"
# "git ls-files -v" tags: S or s skip-worktree, lower case assume-unchanged.
flagged=$(git ls-files -v --full-name -- "$@") || die "git ls-files -v failed"
ignores=$(untracked_ignores "$@") || die "git ls-files failed on the .gitignore files"
changes=$(
  {
    printf '%s\n' "$committed" | awk -F '\t' 'NF { print $1 "\t" $2 "\tHEAD" }'
    printf '%s\n' "$index" | awk -F '\t' 'NF { print $1 "\t" $2 "\tthe index" }'
    printf '%s\n' "$worktree" | awk -F '\t' 'NF { print $1 "\t" $2 "\tthe working tree" }'
    printf '%s\n' "$untracked" | awk 'NF { print "A\t" $0 "\tthe working tree, untracked" }'
    printf '%s\n' "$flagged" | awk '
      { tag = substr($0, 1, 1); path = substr($0, 3) }
      tag == "S" || tag == "s" { print "skip-worktree\t" path "\tthe index" }
      tag != "s" && tag ~ /^[a-z]$/ { print "assume-unchanged\t" path "\tthe index" }
    '
    printf '%s\n' "$ignores" | awk 'NF { print "untracked-gitignore\t" $0 "\tthe working tree" }'
  } | awk -F '\t' '
    # One line per path (per flag and path for a flag), with every place
    # the change is in.
    NF {
      key = $1 ~ /-/ ? $1 "\t" $2 : "\t" $2
      if (!(key in where)) { order[++n] = key; kind[key] = $1; path[key] = $2; where[key] = $3 }
      else if (index(", " where[key] ", ", ", " $3 ", ") == 0) where[key] = where[key] ", " $3
    }
    END { for (i = 1; i <= n; i++) { k = order[i]; print kind[k] "\t" path[k] "\t" where[k] } }
  '
)
[ -n "$changes" ] || exit 0

printf '%s\n' "$changes" | awk -F '\t' -v base="$base" '
  BEGIN { print "check-locked-tests.sh: locked tests differ from " base ":" }
  {
    word = $1 == "D" ? "deleted" : $1 == "A" ? "added" : $1 == "untracked-gitignore" ? "untracked .gitignore" : $1 ~ /-/ ? $1 : "changed"
    print "  " word ": " $2 " (in " $3 ")"
    if ($1 == "skip-worktree" || $1 == "assume-unchanged") flags = 1
    if ($1 == "untracked-gitignore") ignores = 1
  }
  END {
    if (flags) print "  A flagged file hides its changes from git; clear the flag (git update-index --no-skip-worktree or --no-assume-unchanged) and check again."
    if (ignores) print "  An untracked .gitignore in or above a locked path can hide files there from git; only committed ones may: commit it or delete it, and check again."
  }
' >&2
exit 1
