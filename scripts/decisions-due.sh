#!/usr/bin/env bash
# Lists the decisions due for a recheck: every row of a decisions table
# whose Meta column says "recheck YYYY-MM-DD" with a date on or before
# today, unless a later row cleared it: the later row's Decision column
# names the row's ID and that row has a recheck of its own (it took the
# recheck over), or says "Rechecked <ID>" (the recheck was done). A row
# that only names the ID clears nothing. The rows are printed as they
# are, one per line.
#
# Usage: decisions-due.sh [decisions-file] [today]
#   decisions-file defaults to docs/decisions.md
#   today (YYYY-MM-DD) defaults to today's local date
#
# The Meta column is found by its header. Rows without it, such as those
# written before the column existed, are skipped.
#
# A wrapper of `decisions.py due`, next to this script, which needs
# Python 3.10 or later: $PYTHON if set, else python, else python3.
#
# Exit status: 0 whether or not anything is due, 1 a recheck date is
# malformed (each is named on stderr; due rows are still printed),
# 2 bad arguments, no such file or no Python.
set -eu

usage() { echo "Usage: decisions-due.sh [decisions-file] [today]" >&2; exit 2; }
die() { echo "decisions-due.sh: $*" >&2; exit 2; }
case ${1:-} in
  -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
esac
[ "$#" -le 2 ] || usage

file=${1:-docs/decisions.md}
if [ "$#" -ge 2 ]; then today=$2; else today=$(date +%Y-%m-%d); fi
[[ $today =~ ^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$ ]] ||
  die "today must be a date like 2026-11-16, not '$today'"
# Checked here, so the message names the file as given: native Windows
# Python would see the path converted.
[ -f "$file" ] || die "no such file: $file"

# find_python: the first of $PYTHON, python and python3 that is Python
# 3.10 or later (on some systems python is Python 2)
find_python() {
  local p
  for p in "${PYTHON:-}" python python3; do
    [ -n "$p" ] || continue
    if "$p" -c 'import sys; sys.exit(sys.version_info < (3, 10))' > /dev/null 2>&1; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  return 1
}
py=$(find_python) || die "needs Python 3.10 or later: set PYTHON, or put python or python3 on PATH"
exec "$py" "$(dirname "$0")/decisions.py" due --file "$file" --today "$today"
