#!/usr/bin/env bash
# Tests for scripts/check-test-count.sh: every JUnit report the count file
# lists must be complete, with no failed test and exactly the listed number
# of tests run; with --base, no listed count may fall below the base's
# without the owner's approval.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp
clear_git_env # the tests run git; an outer hook's GIT_* must not steer it

COUNT="$ROOT/scripts/check-test-count.sh"

repo="$TMP/project"
git init -q -b main "$repo"
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.com
git -C "$repo" config core.autocrlf false
mkdir -p "$repo/reports" "$repo/ci/reports"

# junit <file> <testcase>...: a Vitest-style report with those testcases
junit() {
  local file=$1 tc
  shift
  {
    printf '<?xml version="1.0" encoding="UTF-8" ?>\n'
    printf '<testsuites name="vitest tests" tests="%d" failures="0" errors="0" time="0.01">\n' "$#"
    printf '    <testsuite name="src/a.test.ts" tests="%d" failures="0" errors="0" skipped="0" time="0.01">\n' "$#"
    for tc in "$@"; do printf '        %s\n' "$tc"; done
    printf '    </testsuite>\n</testsuites>\n'
  } > "$file"
}
PASS='<testcase classname="a" name="passes" time="0.001"></testcase>'
SKIP='<testcase classname="a" name="skipped" time="0"><skipped/></testcase>'
FAIL='<testcase classname="a" name="fails" time="0"><failure message="boom">expected 1</failure></testcase>'
ERROR='<testcase classname="a" name="errors" time="0"><error message="setup"/></testcase>'

reset_repo() {
  rm -rf "$repo/reports"/* "$repo/ci" "$repo/.test-count"
  mkdir -p "$repo/ci/reports"
  junit "$repo/reports/unit.xml" "$PASS" "$PASS" "$PASS"
  junit "$repo/reports/e2e.xml" "$PASS"
  printf '# Tests that must run per JUnit report.\n3 reports/unit.xml\n1 reports/e2e.xml\n' > "$repo/.test-count"
}

# count [args...]: runs the script in the repo; stdout in $TMP/out, stderr
# in $TMP/err
count() { (cd "$repo" && bash "$COUNT" "$@") > "$TMP/out" 2> "$TMP/err"; }
status_is() {
  local want=$1
  shift
  count "$@"
  [ "$?" -eq "$want" ]
}
says() { grep -qF -- "$1" "$TMP/err"; }
# row_is <report> <cells...>: the report's table row, as an extended regex
row_is() {
  local report=$1
  shift
  grep -qE "^$report[[:space:]]+$(printf '%s[[:space:]]+' "$@" | sed 's/\[\[:space:\]\]+$//')\$" "$TMP/out"
}

# --- arguments and the count file
reset_repo
check "--help prints the comment block and no code" help_ok "$COUNT"
check "no arguments: usage error" status_is 2
check "it prints the usage" says 'Usage'
check "two count files: usage error" status_is 2 .test-count .test-count
check "a missing count file: error" status_is 2 nothing.txt
check "it names the file" says nothing.txt
check "--base without a commit: usage error" status_is 2 --base
check "an unknown base: error" status_is 2 --base 1234567890123456789012345678901234567890 .test-count
printf 'three reports/unit.xml\n' > "$repo/.test-count"
check "a malformed line: error" status_is 2 .test-count
check "it names the line" says '.test-count:1'
printf '# nothing yet\n\n' > "$repo/.test-count"
check "a count file listing no report: error" status_is 2 .test-count
printf '3 reports/unit.xml\n2 reports/unit.xml\n' > "$repo/.test-count"
check "a report listed twice: error" status_is 2 .test-count
check "it names the report" says 'reports/unit.xml'
printf '3 reports/unit.xml\napproved-drop reports/unit.xml 4 3 16.11.2026 tidy-up\n' > "$repo/.test-count"
check "an approval with a malformed date: error" status_is 2 .test-count
printf '3 reports/unit.xml\napproved-drop reports/unit.xml 4 3 2026-11-16\n' > "$repo/.test-count"
check "an approval without a reason: error" status_is 2 .test-count
reset_repo

# --- complete reports with the listed counts pass
check "reports with the listed counts pass" status_is 0 .test-count
check "the table shows the unit report" row_is reports/unit.xml 3 3 0 0
check "the table shows the e2e report" row_is reports/e2e.xml 1 1 0 0
check "nothing is reported on stderr" test ! -s "$TMP/err"
printf '3 reports/unit.xml\r\n1 reports/e2e.xml\r\n' > "$repo/.test-count"
check "a CRLF count file passes" status_is 0 .test-count
reset_repo

# --- the report formats of the four runners
cat > "$repo/reports/unit.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?><testsuites><testsuite name="pytest" errors="0" failures="0" skipped="0" tests="3" time="0.1"><testcase classname="tests.test_x" name="test_a" time="0.1" /><testcase classname="tests.test_x" name="test_b" time="0.1"/><testcase classname="tests.test_x" name="test_c" time="0.1"></testcase></testsuite></testsuites>
EOF
check "a one-line pytest report with self-closing testcases passes" status_is 0 .test-count
cat > "$repo/reports/unit.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<testsuites name="nextest-run" tests="3" failures="0" errors="0" uuid="x" timestamp="2026-11-16T10:00:00Z" time="1.0">
    <testsuite name="app" tests="3" disabled="0" errors="0" failures="0">
        <testcase name="tests::f1_1_r1_exports" classname="app" timestamp="2026-11-16T10:00:00Z" time="0.1">
            <flakyFailure message="first try" type="test failure">thread panicked</flakyFailure>
        </testcase>
        <testcase name="tests::f1_2_r1_rejects" classname="app" timestamp="2026-11-16T10:00:00Z" time="0.1"/>
        <testcase name="tests::other" classname="app" timestamp="2026-11-16T10:00:00Z" time="0.1"/>
    </testsuite>
</testsuites>
EOF
check "a nextest report with a flaky pass counts it as passed" status_is 0 .test-count
cat > "$repo/reports/unit.xml" << 'EOF'
<testsuite name="single" tests="3">
  <!-- <testcase name="commented out"/> -->
  <testcase name="a &gt; b" classname="x"/>
  <testcase name='quoted > in an attribute' classname="x"/>
  <testcase name="prints xml" classname="x"><system-out><![CDATA[<testcase name="fake"/><failure/> </testsuite>]]></system-out></testcase>
  <testcases-summary count="9"/>
</testsuite>
EOF
check "a testsuite root, comments, a > in an attribute and CDATA are read right" status_is 0 .test-count
check "exactly three tests are counted" row_is reports/unit.xml 3 3 0 0
reset_repo

# A runner writes a CDATA system-out in each testcase that prints: the
# parser's time must grow linearly with the sections, not with their
# square (5000 of them took 47 s with gawk 5.0 before).
awk 'BEGIN {
  print "<testsuites><testsuite name=\"s\">"
  for (i = 1; i <= 5000; i++)
    printf "<testcase name=\"t%d\"><system-out><![CDATA[%400s]]></system-out><!-- c --></testcase>\n", i, "x"
  print "</testsuite></testsuites>"
}' > "$TMP/big.xml"
started=$SECONDS
LC_ALL=C timeout 120 awk -f "$ROOT/scripts/junit-cases.awk" "$TMP/big.xml" > "$TMP/big.out"
took=$((SECONDS - started))
check "5000 testcases with CDATA sections are all read" \
  test "$(awk -F '\t' '$1 == "C" && $2 == "pass"' "$TMP/big.out" | wc -l)" -eq 5000
check "in under 15 seconds (took ${took}s)" test "$took" -lt 15

# --- a run that did not finish, or no report at all
rm "$repo/reports/e2e.xml"
check "a missing report fails" status_is 1 .test-count
check "it names the report" says 'reports/e2e.xml'
reset_repo
head -c 200 "$repo/reports/unit.xml" > "$repo/reports/cut.xml" && mv "$repo/reports/cut.xml" "$repo/reports/unit.xml"
check "a report cut off mid-write fails" status_is 1 .test-count
check "it names the report" says 'reports/unit.xml'
check "it says it is incomplete" says 'not finish'
reset_repo
: > "$repo/reports/unit.xml"
check "an empty report fails" status_is 1 .test-count
printf 'all tests passed\n' > "$repo/reports/unit.xml"
check "a report that is not JUnit XML fails" status_is 1 .test-count
printf '<testsuites><testsuite><testcase name="a"><skipped/></testsuite></testsuites>\n' > "$repo/reports/unit.xml"
check "a testcase that is never closed fails" status_is 1 .test-count
check "it says the testcase is not closed" says 'never closed'
printf '<testsuites/>\n' > "$repo/reports/unit.xml"
check "an empty but complete report is read as no tests, a drop" status_is 1 .test-count
check "it says the count dropped" says 'dropped'
reset_repo

# --- counts
junit "$repo/reports/unit.xml" "$PASS" "$PASS"
check "fewer tests than listed fails" status_is 1 .test-count
check "it says the count dropped, from and to" says 'dropped from 3 to 2'
refute "it does not blame the other report" says 'e2e.xml'
junit "$repo/reports/unit.xml" "$PASS" "$PASS" "$SKIP"
check "a test switched to skipped is a drop" status_is 1 .test-count
check "the table shows the skipped test" row_is reports/unit.xml 3 2 1 0
junit "$repo/reports/unit.xml" "$PASS" "$PASS" "$PASS" "$PASS"
check "more tests than listed fails until the count file is raised" status_is 1 .test-count
check "it says what to set" says 'set it to 4'
printf '4 reports/unit.xml\n1 reports/e2e.xml\n' > "$repo/.test-count"
check "with the count raised it passes" status_is 0 .test-count
reset_repo

junit "$repo/reports/unit.xml" "$PASS" "$PASS" "$FAIL"
check "a failed test fails" status_is 1 .test-count
check "it says a test failed" says 'failed'
junit "$repo/reports/unit.xml" "$PASS" "$PASS" "$ERROR"
check "an errored test fails" status_is 1 .test-count
reset_repo

# A suite that failed to load reports its error outside any testcase, or
# only in its errors= and failures= counts.
printf '<testsuites><testsuite tests="1" errors="1"><error message="import failed"/><testcase name="a"/></testsuite></testsuites>\n' \
  > "$repo/reports/e2e.xml"
check "an error outside every testcase fails" status_is 1 .test-count
check "it says a test failed or errored" says 'reports/e2e.xml: 1 failed or errored'
printf '<testsuites><testsuite tests="1"><testcase name="a"/><failure message="teardown failed"/></testsuite></testsuites>\n' \
  > "$repo/reports/e2e.xml"
check "a failure element outside every testcase, without counts, fails" status_is 1 .test-count
printf '<testsuites tests="1" failures="2"><testsuite tests="1" failures="2"><testcase name="a"/></testsuite></testsuites>\n' \
  > "$repo/reports/e2e.xml"
check "a failures= count with no failed testcase fails" status_is 1 .test-count
printf '<testsuites tests="1" failures="0" errors="0"><testsuite tests="1" failures="0" errors="0"><testcase name="a"/></testsuite></testsuites>\n' \
  > "$repo/reports/e2e.xml"
check "zero failures= and errors= counts pass" status_is 0 .test-count
reset_repo

# --- a report left from an earlier run: with --since, every report must be
# newer than the stamp file made before the run
touch -t 202601010000 "$repo/reports/unit.xml" "$repo/reports/e2e.xml"
touch "$repo/stamp"
check "a report older than the stamp fails" status_is 1 --since stamp .test-count
check "it names the report" says 'reports/unit.xml'
check "it says the report is from an earlier run" says 'earlier run'
junit "$repo/reports/unit.xml" "$PASS" "$PASS" "$PASS"
junit "$repo/reports/e2e.xml" "$PASS"
touch -t 203001010000 "$repo/reports/unit.xml" "$repo/reports/e2e.xml"
check "reports newer than the stamp pass" status_is 0 --since stamp .test-count
check "a missing stamp file: error" status_is 2 --since no-stamp .test-count
rm -f "$repo/stamp"
reset_repo

# --- paths are relative to the count file's directory
printf '1 reports/ci.xml\n' > "$repo/ci/test-count"
junit "$repo/ci/reports/ci.xml" "$PASS"
check "a report next to a count file in a subdirectory is found" status_is 0 ci/test-count
reset_repo

# --- against the base: a drop needs a new approval
git -C "$repo" add -A
git -C "$repo" commit -q -m "test: count the tests"
base=$(git -C "$repo" rev-parse HEAD)
check "unchanged counts pass against the base" status_is 0 --base "$base" .test-count
check "the table shows the base's count" row_is reports/unit.xml 3 3 3 0 0

junit "$repo/reports/unit.xml" "$PASS" "$PASS"
printf '2 reports/unit.xml\n1 reports/e2e.xml\n' > "$repo/.test-count"
check "the count file lowered to match fewer tests passes without --base" status_is 0 .test-count
check "but fails against the base" status_is 1 --base "$base" .test-count
check "it names the report and both counts" says 'reports/unit.xml: the base lists 3, this lists 2'
printf 'approved-drop reports/unit.xml 3 2 2026-11-16 the CSV exporter was retired\n' >> "$repo/.test-count"
check "a new approval for exactly that drop passes" status_is 0 --base "$base" .test-count
cp "$repo/.test-count" "$TMP/approved"
printf '2 reports/unit.xml\n1 reports/e2e.xml\napproved-drop reports/unit.xml 4 2 2026-11-16 wrong numbers\n' > "$repo/.test-count"
check "an approval with other counts does not pass" status_is 1 --base "$base" .test-count
printf '2 reports/unit.xml\n1 reports/e2e.xml\napproved-drop reports/e2e.xml 3 2 2026-11-16 other report\n' > "$repo/.test-count"
check "an approval for another report does not pass" status_is 1 --base "$base" .test-count
cp "$TMP/approved" "$repo/.test-count"
git -C "$repo" commit -q -am "test: retire the exporter tests"
second=$(git -C "$repo" rev-parse HEAD)
check "after the approved drop is the base, the lower count passes" status_is 0 --base "$second" .test-count
junit "$repo/reports/unit.xml" "$PASS" "$PASS" "$PASS"
printf '3 reports/unit.xml\n1 reports/e2e.xml\napproved-drop reports/unit.xml 3 2 2026-11-16 the CSV exporter was retired\n' > "$repo/.test-count"
git -C "$repo" commit -q -am "test: add a test"
third=$(git -C "$repo" rev-parse HEAD)
junit "$repo/reports/unit.xml" "$PASS" "$PASS"
printf '2 reports/unit.xml\n1 reports/e2e.xml\napproved-drop reports/unit.xml 3 2 2026-11-16 the CSV exporter was retired\n' > "$repo/.test-count"
check "an approval the base already has does not approve a new drop" status_is 1 --base "$third" .test-count
git -C "$repo" reset -q --hard "$base"
reset_repo

printf '3 reports/unit.xml\n' > "$repo/.test-count"
check "a report dropped from the count file fails against the base" status_is 1 --base "$base" .test-count
check "it names the report" says 'reports/e2e.xml'
printf '3 reports/unit.xml\napproved-drop reports/e2e.xml 1 0 2026-11-16 e2e moved to another repo\n' > "$repo/.test-count"
check "an approved removal passes" status_is 0 --base "$base" .test-count
reset_repo

git -C "$repo" rm -q -r --cached .test-count reports
git -C "$repo" commit -q -m "chore: stop tracking the count file"
nocount=$(git -C "$repo" rev-parse HEAD)
check "a base without the count file fails: moving the file would skip the ratchet" \
  status_is 1 --base "$nocount" .test-count
check "it says the base has no count file" says 'no count file'
check "it names the flag for a first count file" says '--allow-new-count-file'
check "a base without the count file passes with --allow-new-count-file, with a note" \
  status_is 0 --base "$nocount" --allow-new-count-file .test-count
check "it says the base has no count file" says 'no count file'
check "--allow-new-count-file without --base: usage error" status_is 2 --allow-new-count-file .test-count
junit "$repo/reports/unit.xml" "$PASS" "$PASS"
printf '2 reports/unit.xml\n1 reports/e2e.xml\n' > "$repo/.test-count"
check "--allow-new-count-file does not excuse a drop when the base has the file" \
  status_is 1 --base "$base" --allow-new-count-file .test-count
check "an absolute count file path with --base: error" status_is 2 --base "$base" "$repo/.test-count"

finish
