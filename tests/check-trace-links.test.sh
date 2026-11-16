#!/usr/bin/env bash
# Tests for scripts/check-trace-links.sh: every feature item must have a
# test that carries its tag at the current revision, and every tag in the
# tests must name a known item at its current revision.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

TRACE="$ROOT/scripts/check-trace-links.sh"

proj="$TMP/project"
mkdir -p "$proj/docs/features" "$proj/e2e" "$proj/tests" "$proj/src"

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
reset_project() {
  rm -rf "$proj/docs/features"/* "$proj/e2e"/* "$proj/tests"/*
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
default_run() { status_is "$1" docs/features e2e tests; }
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
check "a features directory and no test path: usage error" status_is 2 docs/features
check "a missing features directory: error" status_is 2 docs/nothing e2e
check "it names the directory" says docs/nothing
check "a missing test path: error" status_is 2 docs/features e2e/missing.spec.ts
check "it names the path" says e2e/missing.spec.ts
rm -f "$proj/docs/features"/*
check "a features directory without Markdown files: error" status_is 2 docs/features e2e
printf '# Notes\n\nNo table here.\n' > "$proj/docs/features/notes.md"
check "feature files without items: error" status_is 2 docs/features e2e
check "it says no items were found" says 'no feature items'

# --- every link holds
reset_project
check "every item linked at its revision passes" default_run 0
check "the table names the first item" row_is F1-1 1 'e2e/export.spec.ts:3'
check "the table names the Rust test by file and line, at revision 2" row_is F1-2 2 'tests/dates.rs:2'
check "nothing is reported on stderr" test ! -s "$TMP/err"
check "a test file given by name works" status_is 1 docs/features e2e/export.spec.ts
check "the other item then has no test" says F1-2

cat > "$proj/tests/test_dates.py" << 'EOF'
def test_f1_2_r2_rejects_a_bad_from_date():
    assert True
EOF
check "a Python test name counts" default_run 0
check "the item lists both tests" row_is F1-2 2 'tests/dates.rs:2, tests/test_dates.py:1'
reset_project

mkdir -p "$proj/e2e/deep/two words"
printf "it('F1-1-r1 also', () => {});\n" > "$proj/e2e/deep/two words/more.spec.ts"
check "tests in nested directories with spaces are found" default_run 0
check "the nested test is listed" row_has F1-1 'e2e/deep/two words/more.spec.ts:1'
reset_project

printf "test('F1-1-r1 and F1-2-r2 together', () => {});\n" > "$proj/e2e/both.spec.ts"
rm "$proj/tests/dates.rs"
check "one test carrying two tags links both items" default_run 0
check "it is listed under the second item" row_has F1-2 'e2e/both.spec.ts:1'
reset_project

# --- an item without a test
rm "$proj/tests/dates.rs"
check "an item with no test fails" default_run 1
check "it names the item and its revision" says 'F1-2'
check "it gives the tag to use" says 'F1-2-r2'
check "the table shows the item without tests" row_is F1-2 2 '\(none\)'
reset_project

# --- stale and unknown links
edit "$proj/tests/dates.rs" 's/f1_2_r2/f1_2_r1/'
check "a test at an old revision fails" default_run 1
check "it names the file and line" says 'tests/dates.rs:2'
check "it says the link is stale" says 'stale'
check "it says the current revision" says 'r2'
reset_project

edit "$proj/tests/dates.rs" 's/f1_2_r2/f1_2_r3/'
check "a test at a revision the item never had fails" default_run 1
check "it names the revision" says 'f1_2_r3'
reset_project

printf "test('F1-9-r1 ghost', () => {});\n" > "$proj/e2e/ghost.spec.ts"
check "a test naming an unknown item fails" default_run 1
check "it names the unknown item" says 'F1-9'
check "it names the file" says 'e2e/ghost.spec.ts:1'
reset_project

# --- tags that are not in the agreed form
for bad in 'F1-1 ' 'F1-1_r1' 'f1-1-r1' 'F1-1-1' 'F01-1-r1' 'F1-1-r01' 'f1_1'; do
  printf "test('%s spelled wrong', () => {});\n" "$bad" > "$proj/e2e/bad.spec.ts"
  check "the tag '$bad' fails" default_run 1
  check "it is named" says "$(printf '%s' "$bad" | tr -d ' ')"
done
reset_project

# --- word boundaries: a tag inside a longer word is not a tag
printf "test('xF1-1-r1 and F1-1-r10', () => {});\n" > "$proj/e2e/near.spec.ts"
rm "$proj/e2e/export.spec.ts"
check "neither a prefixed tag nor r10 links r1" default_run 1
check "the item has no test" says 'F1-1'
check "r10 is reported" says 'F1-1-r10'
refute "the prefixed tag is not read as a link" row_has F1-1 'near.spec.ts'
printf "test('F1-1-r1x is a longer word', () => {});\n" > "$proj/e2e/near.spec.ts"
check "a letter right after a tag makes it no tag" default_run 1
refute "the suffixed tag is not read as a link" row_has F1-1 'near.spec.ts'
reset_project

printf 'fn helper_f1_1_r1_setup() {}\n' > "$proj/tests/helper.rs"
check "an underscore before the tag is a boundary" default_run 0
check "the helper is listed" row_has F1-1 'tests/helper.rs:1'
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
check "a CRLF feature file with aligned separators passes" status_is 0 docs/features e2e
reset_project

# --- the template: unfilled it fails, filled it passes
cp "$ROOT/templates/feature.md" "$proj/docs/features/export.md"
check "the template's placeholder row fails" default_run 1
sed -e 's/^| F<n>-1 | 1 |/| F1-1 | 1 |/' "$ROOT/templates/feature.md" > "$proj/docs/features/export.md"
check "the filled template differs" test -n "$(diff "$ROOT/templates/feature.md" "$proj/docs/features/export.md")"
rm "$proj/tests/dates.rs"
check "the filled template passes with a linked test" default_run 0
check "the filled template's item is in the table" row_has F1-1 'e2e/export.spec.ts:3'

finish
