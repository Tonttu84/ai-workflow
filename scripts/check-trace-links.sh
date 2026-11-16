#!/usr/bin/env bash
# Checks the links between feature items and tests: every item must have
# a test that ran and passed, whose name carries the item's tag at its
# current revision, and every tag must name a known item at its current
# revision. Prints an item -> tests table on stdout.
#
# Usage: check-trace-links.sh [--scan <test-path>]... <features-dir>
#                             <junit-report>...
#
#   features-dir  holds the feature files, <features-dir>/*.md
#                 (templates/feature.md); items are the rows of the tables
#                 whose first two columns are ID and Rev
#   junit-report  a JUnit XML report of the test run (the ones the count
#                 file lists for check-test-count.sh); only a testcase in
#                 a report links, by its name, and only one that passed:
#                 a tag in a comment, or in a skipped or failed test,
#                 links nothing
#   --scan        a test file or directory, searched recursively (skipping
#                 .git, node_modules and the features directory) for tags
#                 that are stale, unknown or misspelled; it never links
#
# A test links to item F3-2 at revision 1 with the tag F3-2-r1, or
# f3_2_r1 where a name cannot hold "-" (Rust and Python function names).
# A tag is a whole word: a letter or digit before or after it makes it
# part of a longer word, but "_" does not (test_f3_2_r1_name links).
#
# Problems:
#   - an item has no passing test at its current revision;
#   - a tag names an unknown item, or a revision other than the current one;
#   - a test names an item without a revision (F3-2) or in another spelling;
#   - a feature table has a bad ID or Rev, or an ID is used twice;
#   - a feature table has an Item column but no ID and Rev columns, or an
#     item row sits outside an item table;
#   - a report is missing, not JUnit, or not complete.
#
# Exit status: 0 every link holds, 1 a problem (each is named on stderr),
# 2 bad arguments or no feature items at all.
set -eu -o pipefail

usage() { echo "Usage: check-trace-links.sh [--scan <test-path>]... <features-dir> <junit-report>..." >&2; exit 2; }
die() { echo "check-trace-links.sh: $*" >&2; exit 2; }
case ${1:-} in
  -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
esac
here=$(cd "$(dirname "$0")" && pwd)

scans=()
while [ "$#" -gt 0 ]; do
  case $1 in
    --scan) [ "$#" -ge 2 ] || usage; scans+=("$2"); shift 2 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
[ "$#" -ge 2 ] || usage

features=$1
shift
[ -d "$features" ] || die "no such directory: $features"
for report in "$@"; do
  [ -f "$report" ] || die "no such report: $report"
done
for path in ${scans[@]+"${scans[@]}"}; do
  [ -e "$path" ] || die "no such test path: $path"
done
docs=()
while IFS= read -r doc; do docs+=("$doc"); done < <(find "$features" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
[ "${#docs[@]}" -gt 0 ] || die "no Markdown files in $features"

# Items: "I<TAB>id<TAB>rev<TAB>file:line" per row; "Q<TAB>message" per
# problem.
items=$(
  for doc in "${docs[@]}"; do
    awk -f "$here/feature-tables.awk" "$doc" | awk -F '\t' -v doc="$doc" '
      $1 == "X" { printf "Q\t%s:%d: %s\n", doc, $2, $3 }
      $1 == "I" {
        where = doc ":" $2
        if ($3 !~ /^F[1-9][0-9]*-[1-9][0-9]*$/)
          printf "Q\t%s: ID \"%s\" is not F<feature>-<item>, such as F3-2\n", where, $3
        else if ($4 !~ /^[1-9][0-9]*$/)
          printf "Q\t%s: Rev \"%s\" of %s is not a revision number from 1\n", where, $4, $3
        else
          printf "I\t%s\t%s\t%s\n", $3, $4, where
      }
    ' || exit 1
  done
) || die "could not read $features"

# tags(text, where, status): prints "T<TAB>where<TAB>status<TAB>tag" for
# every whole word in the text that looks like an item ID, valid or not.
# SC2016: this is awk code.
# shellcheck disable=SC2016
tags='
  function tags(text, where, status,    line, done, before, after) {
    line = text
    done = 0
    while (match(line, /[Ff][0-9]+[-_][0-9]+([-_][Rr]?[0-9]+)?/)) {
      before = (done + RSTART > 1) ? substr(text, done + RSTART - 1, 1) : ""
      after = substr(line, RSTART + RLENGTH, 1)
      if (before !~ /[A-Za-z0-9]/ && after !~ /[A-Za-z0-9]/)
        printf "T\t%s\t%s\t%s\n", where, status, substr(line, RSTART, RLENGTH)
      done += RSTART + RLENGTH - 1
      line = substr(line, RSTART + RLENGTH)
    }
  }
'

# The testcases of the reports: tags in their names, with each testcase's
# status (pass, skip or fail); "P<TAB>message" for a report that cannot be
# read.
# shellcheck disable=SC2016
named=$(
  for report in "$@"; do
    LC_ALL=C awk -f "$here/junit-cases.awk" "$report" | awk -F '\t' -v report="$report" "$tags"'
      $1 == "E" { printf "P\t%s %s\n", report, $2; bad = 1; exit }
      $1 == "C" { tags($3, report ": " $3, $2) }
      $1 == "O" { done = 1 }
      END { if (!bad && !done) printf "P\t%s could not be read\n", report }
    ' || exit 1
  done
) || die "could not read the reports"

# Tags in the scanned test files, sorted, once each; they never
# link. The features directory is skipped: an item's own Test cell is not
# a test.
# shellcheck disable=SC2016
scanned=$(
  for path in ${scans[@]+"${scans[@]}"}; do
    case $path in -*) path=./$path ;; esac
    find "$path" -type d \( -name .git -o -name node_modules \) -prune -o \
      -type d -exec test {} -ef "$features" \; -prune -o \
      -type f -exec awk "$tags"'{ tags($0, FILENAME ":" FNR, "scan") }' {} + || exit 1
  done | LC_ALL=C sort -u
) || die "could not read the test paths"

printf '%s\n%s\n%s\n' "$items" "$named" "$scanned" | awk -F '\t' '
  function problem(msg) { print "check-trace-links.sh: " msg > "/dev/stderr"; bad = 1 }
  $1 == "P" { problem($2); next }
  $1 == "Q" { problem($2); tables_bad = 1; next }
  $1 == "I" && ($2 in rev) { problem($4 ": " $2 " is used twice (also at " at[$2] ")"); next }
  $1 == "I" { rev[$2] = $3; at[$2] = $4; order[++n] = $2; next }
  $1 == "T" {
    where = $2
    status = $3
    tag = $4
    if (tag !~ /^F[1-9][0-9]*-[1-9][0-9]*-r[1-9][0-9]*$/ && tag !~ /^f[1-9][0-9]*_[1-9][0-9]*_r[1-9][0-9]*$/) {
      problem(where ": " tag " is not an item tag: write F<feature>-<item>-r<rev>, or f<feature>_<item>_r<rev> in a name that cannot hold \"-\"")
      next
    }
    t = tag
    gsub(/_/, "-", t)
    sub(/^f/, "F", t)
    split(t, part, "-")
    id = part[1] "-" part[2]
    r = substr(part[3], 2)
    if (!(id in rev))
      problem(where ": " tag " names " id ", which no feature file has")
    else if (r + 0 < rev[id] + 0)
      problem(where ": " tag " is a stale link: " id " is at r" rev[id] "; recheck the test against the Expected outcome, then rename it to " id "-r" rev[id])
    else if (r != rev[id])
      problem(where ": " tag " names r" r ", but " id " is at r" rev[id])
    else if (status == "pass" && !((id, where) in listed)) {
      listed[id, where] = 1
      tests[id] = tests[id] == "" ? where : tests[id] ", " where
    } else if (status == "skip" || status == "fail")
      other[id] = other[id] == "" ? where " (" status ")" : other[id] ", " where " (" status ")"
  }
  END {
    if (n == 0 && !tables_bad) { print "check-trace-links.sh: no feature items in the feature files" > "/dev/stderr"; exit 2 }
    if (n) printf "%-8s %-4s %s\n", "ID", "Rev", "Tests"
    for (i = 1; i <= n; i++) {
      id = order[i]
      printf "%-8s %-4s %s\n", id, rev[id], tests[id] == "" ? "(none)" : tests[id]
      if (tests[id] != "") continue
      lower = tolower(id)
      gsub(/-/, "_", lower)
      if (other[id] != "")
        problem(id " (r" rev[id] ") has no passing test in the reports; its tests were skipped or failed: " other[id])
      else
        problem(id " (r" rev[id] ") has no test that ran: name one " id "-r" rev[id] " or " lower "_r" rev[id])
    }
    exit bad
  }
'
