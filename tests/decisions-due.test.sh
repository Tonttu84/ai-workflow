#!/usr/bin/env bash
# Tests for scripts/decisions-due.sh: it lists the decision rows whose Meta
# column says "recheck YYYY-MM-DD" on or before today, and reads the
# decisions template without complaint.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

DUE="$ROOT/scripts/decisions-due.sh"

# due [args...]: runs the script; stdout in $TMP/out, stderr in $TMP/err
due() { bash "$DUE" "$@" > "$TMP/out" 2> "$TMP/err"; }
status_is() {
  local want=$1
  shift
  due "$@"
  [ "$?" -eq "$want" ]
}
printed() { grep -qF -- "$1" "$TMP/out"; }
warned() { grep -qF -- "$1" "$TMP/err"; }
lines() { grep -c . "$TMP/out"; }

cat > "$TMP/decisions.md" << 'EOF'
# Decisions

Meta: date · authority · evidence · reversibility · recheck YYYY-MM-DD.

| ID | Decision | Reason | Chosen against | Meta |
| --- | --- | --- | --- | --- |
| D1 | Old row, written before Meta | why | none |
| D2 | Blank Meta | why | none |  |
| D3 | Past | why | none | 2026-01-01 · agent · research normal HIGH (docs/research/a.md) · two-way · recheck 2026-06-01 |
| D4 | Due today | why | none | 2026-01-01 · instruction · none · one-way · recheck 2026-11-16 |
| D5 | Future | why | none | 2026-01-01 · agent · assumed · two-way · recheck 2026-11-17 |
| D6 | Says recheck 2020-01-01 in the decision only | why | none | 2026-01-01 · agent · none · two-way |
| D7 | A cell with an escaped \| pipe | why | none | 2026-01-01 · agent · none · two-way · recheck 2026-02-01 |
| D8 | A report named recheck | why | none | 2026-01-01 · agent · research deep LOW (docs/research/recheck-limits.md) · two-way |

| Other table | Meta is not here | recheck 2020-01-01 |
| --- | --- | --- |
| x | y | recheck 2020-01-01 |
EOF

# --- due and not due
check "a file with due rows exits 0" status_is 0 "$TMP/decisions.md" 2026-11-16
check "a recheck date in the past is due" printed '| D3 |'
check "a recheck date of today is due" printed '| D4 |'
check "an escaped pipe does not shift the columns" printed '| D7 |'
check "the row is printed whole" grep -qxF \
  '| D4 | Due today | why | none | 2026-01-01 · instruction · none · one-way · recheck 2026-11-16 |' "$TMP/out"
refute "a recheck date tomorrow is not due" printed '| D5 |'
refute "a row written before Meta is skipped" printed '| D1 |'
refute "a blank Meta is skipped" printed '| D2 |'
refute "recheck outside the Meta column is ignored" printed '| D6 |'
refute "a path containing recheck is not a recheck" printed '| D8 |'
refute "a table without a Meta column is ignored" printed '| x |'
check "only the due rows are printed" test "$(lines)" -eq 3
check "nothing goes to stderr" test ! -s "$TMP/err"
check "nothing due exits 0 and prints nothing" status_is 0 "$TMP/decisions.md" 2026-01-31
check "it printed nothing" test ! -s "$TMP/out"

# Meta is found by its header, wherever the column is.
cat > "$TMP/moved.md" << 'EOF'
| ID | Meta | Decision |
| --- | --- | --- |
| D1 | 2026-01-01 · agent · none · two-way · recheck 2026-02-01 | moved column |
EOF
check "Meta in another position is found" status_is 0 "$TMP/moved.md" 2026-11-16
check "and its due row printed" printed 'moved column'

# CRLF line endings, as a Windows editor may save them
sed 's/$/\r/' "$TMP/decisions.md" > "$TMP/crlf.md"
check "a CRLF file exits 0" status_is 0 "$TMP/crlf.md" 2026-11-16
check "a CRLF file gives the same rows" test "$(lines)" -eq 3
# (grep in Git for Windows matches $'\r' on every line, so tr does the check)
# SC2094: tr and cmp both only read the file.
# shellcheck disable=SC2094
no_cr() { tr -d '\r' < "$1" | cmp -s - "$1"; }
check "without the carriage returns" no_cr "$TMP/out"
check "the CR check notices a CR" test "$(printf 'a\r\n' > "$TMP/cr" && no_cr "$TMP/cr"; echo $?)" -ne 0

# --- defaults: docs/decisions.md and today's date
mkdir -p "$TMP/project/docs"
cat > "$TMP/project/docs/decisions.md" << 'EOF'
| ID | Decision | Reason | Chosen against | Meta |
| --- | --- | --- | --- | --- |
| D1 | Long past | why | none | 2000-01-01 · agent · none · two-way · recheck 2000-01-02 |
| D2 | Far future | why | none | 2000-01-01 · agent · none · two-way · recheck 2999-12-31 |
EOF
in_project() { (cd "$TMP/project" && bash "$DUE") > "$TMP/out" 2> "$TMP/err"; }
in_project
check "with no arguments it reads docs/decisions.md" test "$?" -eq 0
check "and compares with today's date: the past row is due" printed 'Long past'
refute "the far-future row is not" printed 'Far future'
check "a file and no date uses today's date" status_is 0 "$TMP/project/docs/decisions.md"
check "the same rows" test "$(lines)" -eq 1

# --- malformed recheck dates are reported, not skipped
cat > "$TMP/malformed.md" << 'EOF'
| ID | Decision | Reason | Chosen against | Meta |
| --- | --- | --- | --- | --- |
| D1 | Month 13 | why | none | 2026-01-01 · agent · none · two-way · recheck 2026-13-01 |
| D2 | A word | why | none | 2026-01-01 · agent · none · two-way · recheck soon |
| D3 | Short date | why | none | 2026-01-01 · agent · none · two-way · recheck 2026-1-5 |
| D4 | No date | why | none | 2026-01-01 · agent · none · two-way · recheck |
| D5 | Due and fine | why | none | 2026-01-01 · agent · none · two-way · recheck 2026-02-01 |
EOF
check "malformed recheck dates exit 1" status_is 1 "$TMP/malformed.md" 2026-11-16
for n in 3 4 5 6; do
  check "it names line $n" warned "malformed.md:$n:"
done
check "it still prints the due row" printed '| D5 |'
check "and only that row" test "$(lines)" -eq 1

# --- arguments
check "--help prints the comment block and no code" help_ok "$DUE"
check "a missing file exits 2" status_is 2 "$TMP/no-such.md" 2026-11-16
check "it names the file" warned "$TMP/no-such.md"
missing_default() { (cd "$TMP" && bash "$DUE") > "$TMP/out" 2> "$TMP/err"; }
missing_default
check "no docs/decisions.md here exits 2" test "$?" -eq 2
check "it names docs/decisions.md" warned docs/decisions.md
for bad in 2026-11-31x 2026-1-16 16.11.2026 2026-13-01 2026-11-32 ""; do
  check "today '$bad' is refused" status_is 2 "$TMP/decisions.md" "$bad"
done
check "a third argument is refused" status_is 2 "$TMP/decisions.md" 2026-11-16 extra

# --- the decisions template: in the format the script reads
TEMPLATE="$ROOT/templates/decisions.md"
check "the template has a Meta column" grep -qE '^\| ID \|.*\| Meta \|$' "$TEMPLATE"
check "the template reads without errors" status_is 0 "$TEMPLATE" 2026-11-16
check "without warnings" test ! -s "$TMP/err"
check "its recheck example comes due" status_is 0 "$TEMPLATE" 2999-12-31
check "and is printed" printed 'recheck'

finish
