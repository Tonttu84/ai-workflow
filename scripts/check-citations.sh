#!/usr/bin/env bash
# Checks the citations in a report: every path:line or path:start-end must
# name a file in the repository and lines that file has.
#
# Usage: check-citations.sh <report> [repo-root]
#
#   repo-root  where cited paths start; defaults to the top of the git
#              work tree this runs in, else the current directory
#
# A citation is a path with a "/" or a file extension, then ":" and a
# line or a range: src/app.ts:42, src/app.ts:10-20. A column after it
# (src/app.ts:42:7) is ignored. Write a top-level file without an
# extension as ./Makefile:3. A citation cannot follow a ":", so URLs
# (http://host:8080/a.ts:3) are not read as citations, nor are times
# (10:30) and addresses (127.0.0.1:8080), which have neither; a host name
# with a port outside a URL (example.com:443) is, and fails.
#
# Run it on the commit the report describes: a line number is only
# right for the code it was read from.
#
# Exit status: 0 every citation resolves, 1 a citation does not (each is
# named on stderr with its line in the report) or the report has none,
# 2 bad arguments.
set -eu

usage() { echo "Usage: check-citations.sh <report> [repo-root]" >&2; exit 2; }
die() { echo "check-citations.sh: $*" >&2; exit 2; }
case ${1:-} in
  -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
esac
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then usage; fi
report=$1
[ -f "$report" ] || die "no such report: $report"
if [ "$#" -eq 2 ]; then
  root=$2
else
  root=$(git rev-parse --show-toplevel 2> /dev/null) || root=.
fi
[ -d "$root" ] || die "no such directory: $root"

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

checked=0 bad=0
while IFS=$(printf '\t') read -r at path start end; do
  checked=$((checked + 1))
  where="$report:$at: $path:$start"
  [ "$start" = "$end" ] || where="$where-$end"
  file="$root/$path"
  why=
  # Numbers without leading zeros; more than 9 digits is beyond any file
  # (and beyond what [ can compare).
  first=${start#"${start%%[!0]*}"}
  last=${end#"${end%%[!0]*}"}
  first=${first:-0} last=${last:-0}
  case /$path/ in
    */../*) why="outside the repository" ;;
    */.git/*) why="inside .git, which is not the repository's content" ;;
    *)
      if [ -d "$file" ]; then
        why="a directory, not a file"
      elif [ ! -f "$file" ]; then
        why="no such file"
      else
        length=$(awk 'END { print NR }' "$file")
        if [ "${#first}" -gt 9 ] || [ "${#last}" -gt 9 ]; then
          why="beyond the end of the file ($length lines)"
        elif [ "$first" -lt 1 ] || [ "$last" -lt "$first" ]; then
          why="not a line range"
        elif [ "$last" -gt "$length" ]; then
          why="beyond the end of the file ($length lines)"
        fi
      fi
      ;;
  esac
  if [ -n "$why" ]; then
    echo "check-citations.sh: $where: $why" >&2
    bad=$((bad + 1))
  fi
done <<< "$citations"

noun=citations
[ "$checked" -ne 1 ] || noun=citation
if [ "$bad" -eq 0 ]; then
  echo "$checked $noun checked; all resolve."
else
  echo "$checked $noun checked; $bad do not resolve."
  exit 1
fi
