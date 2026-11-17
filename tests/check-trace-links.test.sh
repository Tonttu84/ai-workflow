#!/usr/bin/env bash
# Tests for scripts/check-trace-links.sh: every feature item must have a
# test that ran and passed, whose name in a JUnit report carries its tag at
# the current revision, and every tag in the reports and the scanned tests
# must name a known item at its current revision.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

TRACE="$ROOT/scripts/check-trace-links.sh"

proj="$TMP/project"
mkdir -p "$proj/docs/features" "$proj/e2e" "$proj/tests" "$proj/src" "$proj/reports"

# feature <file> <rows...>: writes a feature file whose table has the rows
feature() {
  local file=$1 row
  shift
  {
    printf '# Feature F1: export\n\n'
    printf '| ID | Rev | Item | Entry point | Expected outcome | Level | Test |\n'
    printf '| --- | --- | --- | --- | --- | --- | --- |\n'
    for row in "$@"; do printf '%s\n' "$row"; done
    printf '\nLocked tests: e2e at 1234567\n'
  } > "$proj/docs/features/$file"
}
# report <file> <status:name>...: a JUnit report with those testcases;
# status is pass, skip or fail
report() {
  local file=$1 tc status name
  shift
  {
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<testsuites tests="%d">\n  <testsuite name="s" tests="%d">\n' "$#" "$#"
    for tc in "$@"; do
      status=${tc%%:*}
      name=${tc#*:}
      name=$(printf '%s' "$name" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/"/\&quot;/g')
      case $status in
        pass) printf '    <testcase classname="c" name="%s" time="0"/>\n' "$name" ;;
        skip) printf '    <testcase classname="c" name="%s" time="0"><skipped/></testcase>\n' "$name" ;;
        fail) printf '    <testcase classname="c" name="%s" time="0"><failure message="x">x</failure></testcase>\n' "$name" ;;
      esac
    done
    printf '  </testsuite>\n</testsuites>\n'
  } > "$proj/reports/$file"
}
reset_project() {
  rm -rf "$proj/docs/features"/* "$proj/e2e"/* "$proj/tests"/* "$proj/reports"/*
  feature export.md \
    '| F1-1 | 1 | CSV export | Export button | a CSV is saved | — | e2e/export.spec.ts |' \
    '| F1-2 | 2 | Bad dates rejected | /export?from= | a 400 names the field | — | tests/dates.rs |'
  cat > "$proj/e2e/export.spec.ts" << 'EOF'
import { test, expect } from '@playwright/test';

test('F1-1-r1 saves last month as CSV', async ({ page }) => {
  expect(1).toBe(1);
});
EOF
  cat > "$proj/tests/dates.rs" << 'EOF'
#[test]
fn f1_2_r2_rejects_a_bad_from_date() {
    assert!(true);
}
EOF
  report e2e.xml 'pass:F1-1-r1 saves last month as CSV'
  report unit.xml 'pass:tests::f1_2_r2_rejects_a_bad_from_date'
}

# trace [args...]: runs the script in the project; stdout in $TMP/out,
# stderr in $TMP/err
trace() { (cd "$proj" && bash "$TRACE" "$@") > "$TMP/out" 2> "$TMP/err"; }
status_is() {
  local want=$1
  shift
  trace "$@"
  [ "$?" -eq "$want" ]
}
# default_run <status>: the features, every report in reports/, and a scan
# of e2e and tests
default_run() {
  local reports=() r
  for r in "$proj"/reports/*.xml; do [ -f "$r" ] && reports+=("reports/${r##*/}"); done
  status_is "$1" --scan e2e --scan tests docs/features "${reports[@]}"
}
says() { grep -qF -- "$1" "$TMP/err"; }
# row_has <id> <text>: the table row for the item contains the text
row_has() { grep -E "^$1[[:space:]]" "$TMP/out" | grep -qF -- "$2"; }
# row_is <id> <rev> <tests>: the whole row, as an extended regex
row_is() { grep -qE "^$1[[:space:]]+$2[[:space:]]+$3\$" "$TMP/out"; }
# edit <file> <sed script>: edits the file in place, portably
edit() { sed "$2" "$1" > "$1.new" && mv "$1.new" "$1"; }

# --- arguments
check "--help prints the comment block and no code" help_ok "$TRACE"
check "no arguments: usage error" status_is 2
check "it prints the usage" says 'Usage'
reset_project
check "a features directory and no report: usage error" status_is 2 docs/features
check "a missing features directory: error" status_is 2 docs/nothing reports/e2e.xml
check "it names the directory" says docs/nothing
check "a missing report: error" status_is 2 docs/features reports/missing.xml
check "it names the report" says reports/missing.xml
check "a missing scan path: error" status_is 2 --scan e2e/missing.spec.ts docs/features reports/e2e.xml
check "it names the path" says e2e/missing.spec.ts
check "an unknown option: error" status_is 2 --bogus docs/features reports/e2e.xml
rm -f "$proj/docs/features"/*
check "a features directory without Markdown files: error" status_is 2 docs/features reports/e2e.xml
printf '# Notes\n\nNo table here.\n' > "$proj/docs/features/notes.md"
check "feature files without items: error" status_is 2 docs/features reports/e2e.xml
check "it says no items were found" says 'no feature items'

# --- every link holds
reset_project
check "every item linked at its revision passes" default_run 0
check "the table names the first item's test" row_is F1-1 1 'reports/e2e.xml: F1-1-r1 saves last month as CSV'
check "the table names the Rust test at revision 2" row_is F1-2 2 'reports/unit.xml: tests::f1_2_r2_rejects_a_bad_from_date'
check "nothing is reported on stderr" test ! -s "$TMP/err"
check "one report alone" status_is 1 docs/features reports/e2e.xml
check "the other item then has no test" says F1-2
check "without --scan, the reports alone link" status_is 0 docs/features reports/e2e.xml reports/unit.xml

report py.xml 'pass:test_f1_2_r2_rejects_a_bad_from_date'
check "a Python test name counts" default_run 0
check "the item lists both tests" row_is F1-2 2 'reports/py.xml: test_f1_2_r2_rejects_a_bad_from_date, reports/unit.xml: tests::f1_2_r2_rejects_a_bad_from_date'
reset_project

mkdir -p "$proj/e2e/deep/two words" "$proj/reports/two words"
printf "it('F1-1-r1 also', () => {});\n" > "$proj/e2e/deep/two words/more.spec.ts"
check "tests in nested directories with spaces are scanned" default_run 0
printf "it('F1-1-r0 stale', () => {});\n" > "$proj/e2e/deep/two words/more.spec.ts"
check "a bad tag deep in a scanned directory with spaces fails" default_run 1
check "it names the nested file and line" says 'e2e/deep/two words/more.spec.ts:1'
rm -rf "$proj/e2e/deep"
report 'two words/more.xml' 'pass:F1-1-r1 also'
check "a report in a directory with spaces links" \
  status_is 0 docs/features reports/unit.xml 'reports/two words/more.xml'
check "it is listed" row_has F1-1 'reports/two words/more.xml: F1-1-r1 also'
reset_project

report e2e.xml 'pass:F1-1-r1 and F1-2-r2 together'
rm "$proj/reports/unit.xml"
check "one test carrying two tags links both items" default_run 0
check "it is listed under the second item" row_has F1-2 'reports/e2e.xml: F1-1-r1 and F1-2-r2 together'
reset_project

# --- an item without a test that ran and passed
rm "$proj/reports/unit.xml"
check "an item with no test fails" default_run 1
check "it names the item and its revision" says 'F1-2'
check "it gives the tag to use" says 'F1-2-r2'
check "the table shows the item without tests" row_is F1-2 2 '\(none\)'
reset_project

# A tag in a comment, or in a test that was skipped or failed, links
# nothing: only a test that ran and passed does.
cat > "$proj/tests/dates.rs" << 'EOF'
// f1_2_r2: see the exporter
#[test]
#[ignore]
fn f1_2_r2_rejects_a_bad_from_date() {}
EOF
report unit.xml 'skip:tests::f1_2_r2_rejects_a_bad_from_date'
check "a skipped test and a tag in a comment do not link" default_run 1
check "it names the item" says 'F1-2 (r2)'
check "it says the test was skipped" says 'skip'
report unit.xml 'fail:tests::f1_2_r2_rejects_a_bad_from_date'
check "a failed test does not link" default_run 1
check "it says the test failed" says 'fail'
report unit.xml 'pass:tests::other_test'
check "a tag only in a scanned file links nothing" default_run 1
reset_project

# The features directory is never scanned: an item's Test cell is not a
# test (here a stale tag in it would fail the scan).
feature export.md \
  '| F1-1 | 1 | CSV export | Export button | a CSV is saved | — | F1-1-r0 was the old one |' \
  '| F1-2 | 2 | Bad dates rejected | /export?from= | a 400 names the field | — | f1_2_r1 too |'
check "a scan of . skips the features directory" \
  status_is 0 --scan . docs/features reports/e2e.xml reports/unit.xml
reset_project

# A report that is not complete is a problem, not a silent miss.
head -c 60 "$proj/reports/unit.xml" > "$TMP/cut" && mv "$TMP/cut" "$proj/reports/unit.xml"
check "a report cut off mid-write fails" default_run 1
check "it names the report" says 'reports/unit.xml'
printf 'all passed\n' > "$proj/reports/unit.xml"
check "a report that is not JUnit fails" default_run 1
reset_project

# --- stale and unknown links
report unit.xml 'pass:tests::f1_2_r1_rejects_a_bad_from_date'
check "a test at an old revision fails" default_run 1
check "it names the report and test" says 'reports/unit.xml: tests::f1_2_r1_rejects_a_bad_from_date'
check "it says the link is stale" says 'stale'
check "it says the current revision" says 'r2'
reset_project
edit "$proj/tests/dates.rs" 's/f1_2_r2/f1_2_r1/'
check "a scanned test at an old revision fails" default_run 1
check "it names the file and line" says 'tests/dates.rs:2'
check "it says the link is stale" says 'stale'
reset_project

report unit.xml 'pass:tests::f1_2_r3_rejects_a_bad_from_date'
check "a test at a revision the item never had fails" default_run 1
check "it names the revision" says 'f1_2_r3'
reset_project

report ghost.xml 'pass:F1-9-r1 ghost'
check "a test naming an unknown item fails" default_run 1
check "it names the unknown item" says 'F1-9'
check "it names the report" says 'reports/ghost.xml'
reset_project

# --- tags that are not in the agreed form, in a report or a scanned file
for bad in 'F1-1 ' 'F1-1_r1' 'f1-1-r1' 'F1-1-1' 'F01-1-r1' 'F1-1-r01' 'f1_1'; do
  report bad.xml "pass:$bad spelled wrong"
  check "the tag '$bad' in a report fails" default_run 1
  check "it is named" says "$(printf '%s' "$bad" | tr -d ' ')"
  rm "$proj/reports/bad.xml"
  printf "test('%s spelled wrong', () => {});\n" "$bad" > "$proj/e2e/bad.spec.ts"
  check "the tag '$bad' in a scanned file fails" default_run 1
  check "it is named there too" says 'e2e/bad.spec.ts:1'
  rm "$proj/e2e/bad.spec.ts"
done
reset_project

# --- OpenFastTrace IDs (type~name~revision, templates/openfasttrace.md)
# in a scanned file are not item tags, so a project can run both checks
{
  printf '// [itest->feat~f1-1~1]\n'
  printf "test('F1-1-r1 saves it again', () => {});\n"
  printf '// [impl~f1-2-impl~1->feat~f1-2~2]\n'
} > "$proj/e2e/oft.spec.ts"
check "OpenFastTrace tags in a scanned file pass" default_run 0
printf '// [itest->feat~f1-1~1] F1-1 without a revision\n' > "$proj/e2e/oft.spec.ts"
check "an item tag next to an OpenFastTrace tag is still read" default_run 1
check "it is named" says 'e2e/oft.spec.ts:1: F1-1 is not an item tag'
reset_project

# --- word boundaries: a tag inside a longer word is not a tag
report e2e.xml 'pass:xF1-1-r1 and F1-1-r10'
check "neither a prefixed tag nor r10 links r1" default_run 1
check "the item has no test" says 'F1-1'
check "r10 is reported" says 'F1-1-r10'
refute "the prefixed tag is not read as a link" row_has F1-1 'xF1'
report e2e.xml 'pass:F1-1-r1x is a longer word'
check "a letter right after a tag makes it no tag" default_run 1
refute "the suffixed tag is not read as a link" row_has F1-1 'longer word'
reset_project

report helper.xml 'pass:helper_f1_1_r1_setup'
check "an underscore before the tag is a boundary" default_run 0
check "the helper is listed" row_has F1-1 'reports/helper.xml: helper_f1_1_r1_setup'
reset_project

# Entities in a name are decoded before the tag is read.
report e2e.xml 'pass:<b>F1-1-r1</b> & more'
check "a name with XML entities links" default_run 0
check "it is listed decoded" row_has F1-1 'reports/e2e.xml: <b>F1-1-r1</b> & more'
reset_project

# --- feature tables
feature second.md '| F1-1 | 1 | Same ID | x | y | — | z |'
check "a duplicate ID across files fails" default_run 1
check "it names the duplicate" says 'F1-1'
reset_project

feature export.md '| F<n>-1 | 1 | Placeholder | x | y | — | z |'
check "an unfilled ID fails" default_run 1
check "it names the bad ID" says 'F<n>-1'
reset_project

for rev in 0 '' 'r1' 01; do
  feature export.md "| F1-1 | $rev | Item | x | y | — | e2e |"
  check "Rev '$rev' fails" default_run 1
  check "it names the file" says 'export.md'
done
reset_project

{
  printf '| Item | Entry point | Expected outcome | Level | Test |\n'
  printf '| --- | --- | --- | --- | --- |\n'
  printf '| Old item | x | y | — | z |\n'
} > "$proj/docs/features/legacy.md"
check "a feature table without ID and Rev columns fails" default_run 1
check "it names the file" says 'legacy.md'
reset_project

printf '| ID | Rev | Item | Entry point | Expected outcome | Level | Test |\r\n| :--- | :---: | --- | --- | --- | --- | --- |\r\n| F1-1 | 1 | a | b | c | — | d |\r\n' \
  > "$proj/docs/features/export.md"
check "a CRLF feature file with aligned separators passes" status_is 0 docs/features reports/e2e.xml
reset_project

# Tables as GitHub Markdown reads them: the outer pipes are optional.
feature export.md \
  '| F1-1 | 1 | CSV export | Export button | a CSV is saved | — | e2e/export.spec.ts |' \
  '| F1-2 | 2 | Bad dates rejected | /export?from= | a 400 names the field | — | tests/dates.rs |' \
  'F1-3 | 1 | No pipe first | x | y | — | z |'
check "a row without its leading pipe is an item: with no test it fails" default_run 1
check "it names the item" says 'F1-3'
{
  printf 'ID | Rev | Item | Entry point | Expected outcome | Level | Test\n'
  printf -- '--- | --- | --- | --- | --- | --- | ---\n'
  printf 'F1-1 | 1 | a | b | c | — | d\nF1-2 | 2 | a | b | c | — | d\nF1-3 | 1 | a | b | c | — | d\n'
} > "$proj/docs/features/export.md"
check "a table without outer pipes is read: its untested item fails" default_run 1
check "it names that item" says 'F1-3 (r1)'
printf '| Id | Rev | Thing |\n| --- | --- | --- |\n| F2-1 | 1 | x |\n' > "$proj/docs/features/other.md"
feature export.md \
  '| F1-1 | 1 | CSV export | Export button | a CSV is saved | — | e2e/export.spec.ts |' \
  '| F1-2 | 2 | Bad dates rejected | /export?from= | a 400 names the field | — | tests/dates.rs |'
check "an item row in a table that is not an item table fails" default_run 1
check "it names the row" says 'F2-1'
check "it names the file and line" says 'other.md:3'
reset_project

# --- a failing find or awk is an error, not a silent miss
mkdir -p "$TMP/fakebin"
# The fake find fails the scan (the only call with -prune) and passes the
# rest to the real one.
# shellcheck disable=SC2016
printf '#!/bin/sh\ncase "$*" in *-prune*) exit 1 ;; esac\nexec %s "$@"\n' "$(command -v find)" > "$TMP/fakebin/find"
chmod +x "$TMP/fakebin/find"
fake_find() { (cd "$proj" && PATH="$TMP/fakebin:$PATH" bash "$TRACE" --scan e2e docs/features reports/e2e.xml reports/unit.xml) > "$TMP/out" 2> "$TMP/err"; }
fake_find
check "a find that fails: error" test "$?" -eq 2
rm -f "$TMP/fakebin/find"

# --- the template: unfilled it fails, filled it passes
cp "$ROOT/templates/feature.md" "$proj/docs/features/export.md"
check "the template's placeholder row fails" default_run 1
sed -e 's/^| F<n>-1 | 1 |/| F1-1 | 1 |/' "$ROOT/templates/feature.md" > "$proj/docs/features/export.md"
check "the filled template differs" test -n "$(diff "$ROOT/templates/feature.md" "$proj/docs/features/export.md")"
rm "$proj/tests/dates.rs" "$proj/reports/unit.xml"
check "the filled template passes with a linked test" default_run 0
check "the filled template's item is in the table" row_has F1-1 'reports/e2e.xml: F1-1-r1 saves last month as CSV'

finish
