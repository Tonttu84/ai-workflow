#!/usr/bin/env bash
# Checks that the test runner finished and the number of tests did not
# drop, from JUnit XML reports (Vitest, Playwright, pytest and
# cargo-nextest can all write them).
#
# Usage: check-test-count.sh [--base <commit>] <count-file>
#
# The count file is committed. Each line names a report, relative to the
# count file's directory (no spaces in the path), and how many tests must
# run in it; blank lines and lines starting with # are ignored:
#
#   120 reports/unit.xml
#   14 reports/e2e.xml
#   approved-drop reports/unit.xml 121 120 2026-11-16 <reason>
#
# Every listed report must be complete (a closed <testsuites> or
# <testsuite> root), with no failed or errored test, and exactly the
# listed number of tests run (skipped ones do not count). More tests than
# listed also fails, until the count file is raised: a count left low
# would let later tests go unnoticed. Delete the reports before the test
# run, or a report left from an earlier run is read as this one's.
#
# With --base (such as the remote branch the push goes to), the count
# file is also compared with its version in that commit: a count below
# the base's, or a report the base lists and this does not (count 0),
# fails unless an approved-drop line names that report and exactly those
# two counts. Only the owner approves a drop; the line records the date
# and reason, and it counts only in the change that adds it (a line the
# base already has approves nothing). A base without the count file is
# noted and not compared. The count file path must then be relative.
#
# Exit status: 0 everything holds, 1 a report is missing, incomplete or
# unreadable, a test failed, or a count differs (each is named on
# stderr), 2 bad arguments or a malformed count file.
set -eu

usage() { echo "Usage: check-test-count.sh [--base <commit>] <count-file>" >&2; exit 2; }
die() { echo "check-test-count.sh: $*" >&2; exit 2; }
case ${1:-} in
  -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
esac

base=
if [ "${1:-}" = --base ]; then
  [ "$#" -ge 2 ] || usage
  base=$2
  shift 2
fi
[ "$#" -eq 1 ] || usage
file=$1
[ -f "$file" ] || die "no such count file: $file"
dir=$(dirname "$file")

# parse <name>: reads a count file on stdin and prints
# "C<TAB>report<TAB>count" and "A<TAB>report<TAB>from<TAB>to<TAB>line";
# a malformed line is named on stderr, with status 2.
parse() {
  awk -v name="$1" '
    function bad(msg) { printf "check-test-count.sh: %s:%d: %s\n", name, NR, msg > "/dev/stderr"; failed = 1 }
    { sub(/\r$/, "") }
    /^[ \t]*(#|$)/ { next }
    $1 ~ /^[0-9]+$/ && NF == 2 {
      if ($2 in seen) bad($2 " is listed twice")
      seen[$2] = 1
      printf "C\t%s\t%d\n", $2, $1
      next
    }
    $1 == "approved-drop" {
      if (NF < 6 || $3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ || $5 !~ /^[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]$/)
        bad("not \"approved-drop <report> <from> <to> <YYYY-MM-DD> <reason>\"")
      else {
        line = $1
        for (i = 2; i <= NF; i++) line = line " " $i
        printf "A\t%s\t%d\t%d\t%s\n", $2, $3, $4, line
      }
      next
    }
    { bad("not \"<count> <report>\" or an approved-drop line: " $0) }
    END { exit failed ? 2 : 0 }
  '
}

current=$(parse "$file" < "$file") || exit 2
printf '%s\n' "$current" | grep -q '^C' || die "$file lists no report"

previous=
if [ -n "$base" ]; then
  case $file in /* | [A-Za-z]:*) die "with --base, give the count file relative to the current directory: $file" ;; esac
  git rev-parse --is-inside-work-tree > /dev/null 2>&1 || die "--base needs a git work tree"
  commit=$(git rev-parse --verify --quiet "$base^{commit}") || die "unknown commit: $base"
  if git cat-file -e "$commit:./$file" 2> /dev/null; then
    previous=$(git show "$commit:./$file" | parse "$base:$file") || exit 2
    previous=$(printf '%s\n' "$previous" | sed 's/^C/B/; s/^A/O/')
  else
    echo "check-test-count.sh: the base $base has no count file at $file: nothing to compare with" >&2
    previous=none
  fi
fi

# junit <report>: "J<TAB>report<TAB>tests<TAB>skipped<TAB>failed", or
# "E<TAB>report<TAB>message" when the report cannot be read as complete.
junit() {
  local path=$1 xml="$dir/$1"
  if [ ! -f "$xml" ]; then printf 'E\t%s\tno such report\n' "$path"; return; fi
  LC_ALL=C awk -v report="$path" '
    function problem(msg) { if (!err) printf "E\t%s\t%s\n", report, msg; err = 1 }
    # strip(s, start, end): s without every start...end section
    function strip(s, start, end,    i, j, out) {
      out = ""
      while ((i = index(s, start)) > 0) {
        out = out substr(s, 1, i - 1)
        s = substr(s, i + length(start))
        if ((j = index(s, end)) == 0) { problem("an unclosed " start " section: the runner did not finish writing it"); return out }
        s = substr(s, j + length(end))
      }
      return out s
    }
    # tag_end(s): where the tag that s starts with ends, quotes respected
    function tag_end(s,    i, n, c, q) {
      n = length(s)
      q = ""
      for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        if (q != "") { if (c == q) q = "" }
        else if (c == "\"" || c == "\047") q = c
        else if (c == ">") return i
      }
      return 0
    }
    { sub(/\r$/, ""); s = s $0 "\n" }
    END {
      s = strip(s, "<![CDATA[", "]]>")
      s = strip(s, "<!--", "-->")
      s = strip(s, "<?", "?>")
      sub(/^[ \t\n]+/, "", s)
      sub(/[ \t\n]+$/, "", s)
      if (s == "") problem("is empty")
      else if (s !~ /^<testsuites?[ \t\n\/>]/) problem("has no <testsuites> or <testsuite> root: not a JUnit report")
      else {
        root = s ~ /^<testsuites[ \t\n\/>]/ ? "testsuites" : "testsuite"
        closed = substr(s, length(s) - length(root) - 2) == "</" root ">"
        empty = tag_end(s) == length(s) && substr(s, length(s) - 1) == "/>" # <testsuites/>
        if (!closed && !empty) problem("is not closed: the runner did not finish writing it")
      }
      if (err) exit
      n = split(s, part, "<testcase")
      for (i = 2; i <= n; i++) {
        p = part[i]
        if (substr(p, 1, 1) !~ /[ \t\n\/>]/) continue # a longer tag name
        e = tag_end(p)
        if (e == 0) { problem("a <testcase> tag is not closed"); exit }
        tests++
        if (substr(p, e - 1, 1) == "/") continue # <testcase .../>
        k = index(p, "</testcase>")
        if (k == 0) { problem("a <testcase> is never closed"); exit }
        body = substr(p, e + 1, k - e - 1)
        if (body ~ /<skipped[ \t\n\/>]/) skipped++
        else if (body ~ /<(failure|error)[ \t\n\/>]/) failed++
      }
      printf "J\t%s\t%d\t%d\t%d\n", report, tests, skipped, failed
    }
  ' "$xml"
}

results=$(
  printf '%s\n' "$current" | awk -F '\t' '$1 == "C" { print $2 }' | while IFS= read -r report; do
    junit "$report"
  done
)

printf '%s\n%s\n%s\n' "$current" "$previous" "$results" | awk -F '\t' -v file="$file" -v base="$base" '
  function problem(msg) { print "check-test-count.sh: " msg > "/dev/stderr"; bad = 1 }
  $1 == "C" { listed[$2] = $3; order[++n] = $2; next }
  $1 == "A" { approved[$2, $3, $4] = $5; next }
  $1 == "B" { before[$2] = $3; border[++nb] = $2; next }
  $1 == "O" { old[$5] = 1; next }
  $1 == "J" { tests[$2] = $3; skipped[$2] = $4; failed[$2] = $5; next }
  $1 == "E" { error[$2] = $3; next }
  END {
    for (i = 1; i <= n; i++) {
      r = order[i]
      if (r in error) { problem(r ": " error[r]); continue }
      ran = tests[r] - skipped[r]
      if (failed[r] > 0) problem(r ": " failed[r] " failed or errored tests")
      if (ran < listed[r]) problem(r ": the test count dropped from " listed[r] " to " ran)
      if (ran > listed[r]) problem(r ": " ran " tests ran, " file " lists " listed[r] ": set it to " ran)
    }
    for (i = 1; i <= nb; i++) {
      r = border[i]
      now = (r in listed) ? listed[r] : 0
      if (now >= before[r]) continue
      key = r SUBSEP before[r] SUBSEP now
      if ((key in approved) && !(approved[key] in old)) continue
      problem(r ": the base lists " before[r] ", this lists " ((r in listed) ? now : "none") \
        ": a drop needs the owner to approve it with a new line \"approved-drop " r " " before[r] " " now " <YYYY-MM-DD> <reason>\"")
    }
    withbase = base != "" && nb > 0
    if (withbase) printf "%-30s %6s %6s %6s %8s %6s\n", "Report", "Base", "Listed", "Ran", "Skipped", "Failed"
    else printf "%-30s %6s %6s %8s %6s\n", "Report", "Listed", "Ran", "Skipped", "Failed"
    for (i = 1; i <= n; i++) {
      r = order[i]
      was = (r in before) ? before[r] : "-"
      if (r in error) { ran = "?"; sk = "?"; fl = "?" } else { ran = tests[r] - skipped[r]; sk = skipped[r]; fl = failed[r] }
      if (withbase) printf "%-30s %6s %6s %6s %8s %6s\n", r, was, listed[r], ran, sk, fl
      else printf "%-30s %6s %6s %8s %6s\n", r, listed[r], ran, sk, fl
    }
    exit bad
  }
'
