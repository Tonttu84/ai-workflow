#!/usr/bin/env bash
# Lists the decisions due for a recheck: every row of a decisions table
# whose Meta column says "recheck YYYY-MM-DD" with a date on or before
# today. The rows are printed as they are, one per line.
#
# Usage: decisions-due.sh [decisions-file] [today]
#   decisions-file defaults to docs/decisions.md
#   today (YYYY-MM-DD) defaults to today's local date
#
# The Meta column is found by its header. Rows without it, such as those
# written before the column existed, are skipped.
#
# Exit status: 0 whether or not anything is due, 1 a recheck date is
# malformed (each is named on stderr; due rows are still printed),
# 2 bad arguments or no such file.
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
[ -f "$file" ] || die "no such file: $file"

awk -v today="$today" -v name="$file" '
  function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
  # cells(row): splits a table row on pipes that are not escaped as \|
  function cells(row,    n, i, part) {
    gsub(/\\\|/, "\001", row)
    sub(/^[ \t]*\|/, "", row)
    sub(/\|[ \t]*$/, "", row)
    n = split(row, part, "|")
    for (i = 1; i <= n; i++) cell[i] = trim(part[i])
    return n
  }
  function valid(d,    month, day) {
    if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
    month = substr(d, 6, 2) + 0
    day = substr(d, 9, 2) + 0
    return month >= 1 && month <= 12 && day >= 1 && day <= 31
  }
  { sub(/\r$/, "") }
  !/^[ \t]*\|/ { intable = 0; next }
  !intable {  # the header row: find the Meta column
    intable = 1
    meta = 0
    n = cells($0)
    for (i = 1; i <= n; i++) if (cell[i] == "Meta") meta = i
    next
  }
  /^[ \t]*\|[ \t:|-]*$/ { next }  # the separator row
  meta && cells($0) >= meta && match(cell[meta], /(^|[ \t])recheck/) {
    date = substr(cell[meta], RSTART + RLENGTH)
    if ((i = index(date, "·")) > 0) date = substr(date, 1, i - 1)
    date = trim(date)
    if (!valid(date)) {
      printf "decisions-due.sh: %s:%d: malformed recheck date: \"%s\"\n", name, FNR, date > "/dev/stderr"
      bad = 1
    } else if (date <= today) {
      print
    }
  }
  END { exit bad }
' "$file"
