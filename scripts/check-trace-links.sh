#!/usr/bin/env bash
# Checks the links between feature items and tests: every item must have
# a test that carries its tag at the item's current revision, and every
# tag in the tests must name a known item at its current revision. Prints
# an item -> tests table on stdout.
#
# Usage: check-trace-links.sh <features-dir> <test-path>...
#
# Items are the rows of the tables whose first two columns are ID and Rev
# in <features-dir>/*.md (templates/feature.md). Test paths are files or
# directories, searched recursively (skipping .git and node_modules);
# paths are relative to the current directory.
#
# A test links to item F3-2 at revision 1 with the tag F3-2-r1, or
# f3_2_r1 where a name cannot hold "-" (Rust and Python function names).
# A tag is a whole word: a letter or digit before or after it makes it
# part of a longer word, but "_" does not (test_f3_2_r1_name links).
#
# Problems:
#   - an item has no test at its current revision;
#   - a tag names an unknown item, or a revision other than the current one;
#   - a test names an item without a revision (F3-2) or in another spelling;
#   - a feature table has a bad ID or Rev, or an ID is used twice;
#   - a feature table has an Item column but no ID and Rev columns.
#
# Exit status: 0 every link holds, 1 a problem (each is named on stderr),
# 2 bad arguments or no feature items at all.
set -eu

usage() { echo "Usage: check-trace-links.sh <features-dir> <test-path>..." >&2; exit 2; }
die() { echo "check-trace-links.sh: $*" >&2; exit 2; }
case ${1:-} in
  -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
esac
[ "$#" -ge 2 ] || usage

features=$1
shift
[ -d "$features" ] || die "no such directory: $features"
for path in "$@"; do
  [ -e "$path" ] || die "no such test path: $path"
done
docs=()
while IFS= read -r doc; do docs+=("$doc"); done < <(find "$features" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
[ "${#docs[@]}" -gt 0 ] || die "no Markdown files in $features"

# Items: "I<TAB>id<TAB>rev<TAB>file:line" per row; "P<TAB>message" per
# problem.
items=$(
  awk '
      function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
      function cells(row,    n, i, part) {
        gsub(/\\\|/, "\001", row)
        sub(/^[ \t]*\|/, "", row)
        sub(/\|[ \t]*$/, "", row)
        n = split(row, part, "|")
        for (i = 1; i <= n; i++) cell[i] = trim(part[i])
        return n
      }
      function separator(n,    i) {
        for (i = 1; i <= n; i++) if (cell[i] !~ /^:?-+:?$/) return 0
        return 1
      }
      { sub(/\r$/, "") }
      FNR == 1 { intable = 0 }
      !/^[ \t]*\|/ { intable = 0; next }
      !intable {
        intable = 1
        n = cells($0)
        items = cell[1] == "ID" && cell[2] == "Rev"
        if (!items)
          for (i = 1; i <= n; i++)
            if (cell[i] == "Item")
              printf "P\t%s:%d: a feature table without ID and Rev as its first columns\n", FILENAME, FNR
        next
      }
      !items { next }
      {
        n = cells($0)
        if (separator(n)) next
        where = FILENAME ":" FNR
        if (cell[1] !~ /^F[1-9][0-9]*-[1-9][0-9]*$/)
          printf "P\t%s: ID \"%s\" is not F<feature>-<item>, such as F3-2\n", where, cell[1]
        else if (cell[2] !~ /^[1-9][0-9]*$/)
          printf "P\t%s: Rev \"%s\" of %s is not a revision number from 1\n", where, cell[2], cell[1]
        else
          printf "I\t%s\t%s\t%s\n", cell[1], cell[2], where
      }
    ' "${docs[@]}"
) || die "could not read $features"

# Tags: "T<TAB>file<TAB>line<TAB>tag" for every whole word that looks like
# an item ID, valid or not, sorted by file and line.
tags=$(
  for path in "$@"; do
    case $path in -*) path=./$path ;; esac
    find "$path" \( -name .git -o -name node_modules \) -prune -o -type f -exec awk '
      {
        line = $0
        done = 0
        while (match(line, /[Ff][0-9]+[-_][0-9]+([-_][Rr]?[0-9]+)?/)) {
          before = (done + RSTART > 1) ? substr($0, done + RSTART - 1, 1) : ""
          after = substr(line, RSTART + RLENGTH, 1)
          if (before !~ /[A-Za-z0-9]/ && after !~ /[A-Za-z0-9]/)
            printf "T\t%s\t%d\t%s\n", FILENAME, FNR, substr(line, RSTART, RLENGTH)
          done += RSTART + RLENGTH - 1
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' {} +
  done | LC_ALL=C sort -t "$(printf '\t')" -k2,2 -k3,3n -k4,4 -u
) || die "could not read the test paths"

printf '%s\n%s\n' "$items" "$tags" | awk -F '\t' '
  function problem(msg) { print "check-trace-links.sh: " msg > "/dev/stderr"; bad = 1 }
  $1 == "P" { problem($2); tables_bad = 1; next }
  $1 == "I" && ($2 in rev) { problem($4 ": " $2 " is used twice (also at " at[$2] ")"); next }
  $1 == "I" { rev[$2] = $3; at[$2] = $4; order[++n] = $2; next }
  $1 == "T" {
    where = $2 ":" $3
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
    else if (!((id, where) in listed)) {
      listed[id, where] = 1
      tests[id] = tests[id] == "" ? where : tests[id] ", " where
    }
  }
  END {
    if (n == 0 && !tables_bad) { print "check-trace-links.sh: no feature items in the feature files" > "/dev/stderr"; exit 2 }
    if (n) printf "%-8s %-4s %s\n", "ID", "Rev", "Tests"
    for (i = 1; i <= n; i++) {
      id = order[i]
      printf "%-8s %-4s %s\n", id, rev[id], tests[id] == "" ? "(none)" : tests[id]
      if (tests[id] == "") {
        lower = tolower(id)
        gsub(/-/, "_", lower)
        problem(id " (r" rev[id] ") has no test: name one " id "-r" rev[id] " or " lower "_r" rev[id])
      }
    }
    exit bad
  }
'
