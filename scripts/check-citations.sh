#!/usr/bin/env bash
# Checks the citations in a report: every path:line or path:start-end must
# name a file committed at a revision and lines that file has there.
#
# Usage: check-citations.sh [--rev <commit>] <report> [repo-root]
#
#   --rev      the commit the report describes (default HEAD): each file
#              is read as committed there, never from the working tree
#   repo-root  where cited paths start, in a git work tree; defaults to
#              the top of the git work tree this runs in
#
# A citation is a path with a "/" or a file extension, then ":" and a
# line or a range: src/app.ts:42, src/app.ts:10-20. A column after it
# (src/app.ts:42:7) is ignored. Write a top-level file without an
# extension as ./Makefile:3. A citation cannot follow a ":", so URLs
# (http://host:8080/a.ts:3) are not read as citations, nor are times
# (10:30) and addresses (127.0.0.1:8080), which have neither; a host name
# with a port outside a URL (example.com:443) is, and fails.
#
# Only a file committed at the revision resolves: an untracked or ignored
# file (a dependency under node_modules/, say), a change not committed, a
# directory, a symbolic link, a path that leaves the repository and a
# path inside .git (in any case) all fail. A line number is only right
# for the code it was read from, so give --rev the commit the report
# was written against.
#
# Exit status: 0 every citation resolves, 1 a citation does not (each is
# named on stderr with its line in the report) or the report has none,
# 2 bad arguments.
set -eu

usage() { echo "Usage: check-citations.sh [--rev <commit>] <report> [repo-root]" >&2; exit 2; }
die() { echo "check-citations.sh: $*" >&2; exit 2; }
case ${1:-} in
  -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
esac
rev=HEAD
if [ "${1:-}" = --rev ]; then
  [ "$#" -ge 2 ] || usage
  rev=$2
  shift 2
fi
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then usage; fi
report=$1
[ -f "$report" ] || die "no such report: $report"
if [ "$#" -eq 2 ]; then
  root=$2
  [ -d "$root" ] || die "no such directory: $root"
else
  root=$(git rev-parse --show-toplevel 2> /dev/null) || die "not inside a git work tree"
fi
# Paths are literal, never globs, and non-ASCII names print as they are.
git() { command git -C "$root" --literal-pathspecs -c core.quotePath=false "$@"; }
prefix=$(git rev-parse --show-prefix 2> /dev/null) || die "$root is not inside a git work tree"
commit=$(git rev-parse --verify --quiet "$rev^{commit}") || die "unknown commit: $rev"
short=$(git rev-parse --short "$commit")

# "<report line><TAB><path><TAB><start><TAB><end>" per citation
citations=$(awk '
  {
    sub(/\r$/, "")
    line = $0
    done = 0
    while (match(line, /[A-Za-z0-9_.\/@+~-]+:[0-9]+(-[0-9]+)?/)) {
      before = (done + RSTART > 1) ? substr($0, done + RSTART - 1, 1) : ""
      cite = substr(line, RSTART, RLENGTH)
      done += RSTART + RLENGTH - 1
      line = substr(line, RSTART + RLENGTH)
      if (before ~ /[A-Za-z0-9_.\/@+~:-]/) continue
      path = cite
      sub(/:[0-9]+(-[0-9]+)?$/, "", path)
      if (path !~ /\// && path !~ /\.[A-Za-z]/) continue
      lines = substr(cite, length(path) + 2)
      start = lines
      sub(/-.*/, "", start)
      end = lines
      sub(/.*-/, "", end)
      printf "%d\t%s\t%s\t%s\n", FNR, path, start, end
    }
  }
' "$report")

[ -n "$citations" ] || {
  echo "check-citations.sh: no path:line citations in $report" >&2
  exit 1
}

# entry <path from the top>: "<mode> <type> <object>" of the path at the
# commit, or nothing when the commit does not have it under that exact
# name (git may match a pathspec without regard to case)
entry() {
  local line
  while IFS= read -r -d '' line; do
    if [ "${line#*$'\t'}" = "$1" ]; then
      printf '%s\n' "${line%%$'\t'*}"
      return 0
    fi
  done < <(git ls-tree -z --full-tree "$commit" -- "$1")
}

checked=0 bad=0
while IFS=$(printf '\t') read -r at path start end; do
  checked=$((checked + 1))
  where="$report:$at: $path:$start"
  [ "$start" = "$end" ] || where="$where-$end"
  why=
  # Numbers without leading zeros; more than 9 digits is beyond any file
  # (and beyond what [ can compare).
  first=${start#"${start%%[!0]*}"}
  last=${end#"${end%%[!0]*}"}
  first=${first:-0} last=${last:-0}
  # The path from the top: ./ and a trailing / dropped.
  name=/$path/
  while :; do
    case $name in
      */./*) name=${name%%/./*}/${name#*/./} ;;
      *//*) name=${name%%//*}/${name#*//} ;;
      *) break ;;
    esac
  done
  name=${name#/}
  name=$prefix${name%/}
  case /$(printf '%s' "$path" | tr '[:upper:]' '[:lower:]')/ in
    */../*) why="outside the repository" ;;
    */.git/*) why="inside .git, which is not the repository's content" ;;
  esac
  if [ -z "$why" ]; then
    meta=$(entry "$name")
    read -r mode type sha <<< "$meta"
    case $mode:$type in
      :) why="no such file at $short: only committed files count, not an untracked or ignored one, nor a change not committed" ;;
      120000:*) why="a symbolic link, not a file" ;;
      *:tree) why="a directory, not a file" ;;
      *:blob)
        length=$(git cat-file blob "$sha" | awk 'END { print NR }')
        if [ "${#first}" -gt 9 ] || [ "${#last}" -gt 9 ]; then
          why="beyond the end of the file ($length lines)"
        elif [ "$first" -lt 1 ] || [ "$last" -lt "$first" ]; then
          why="not a line range"
        elif [ "$last" -gt "$length" ]; then
          why="beyond the end of the file ($length lines)"
        fi ;;
      *) why="not a file (a $type)" ;;
    esac
  fi
  if [ -n "$why" ]; then
    echo "check-citations.sh: $where: $why" >&2
    bad=$((bad + 1))
  fi
done <<< "$citations"

noun=citations
[ "$checked" -ne 1 ] || noun=citation
if [ "$bad" -eq 0 ]; then
  echo "$checked $noun checked at $short; all resolve."
else
  echo "$checked $noun checked at $short; $bad do not resolve."
  exit 1
fi
