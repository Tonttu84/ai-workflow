#!/usr/bin/env bash
# Tests for scripts/check-citations.sh: every path:line or path:start-end
# citation in a report must name a file in the repository and lines that
# file has.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp
clear_git_env # the tests run git; an outer hook's GIT_* must not steer it

CITE="$ROOT/scripts/check-citations.sh"

repo="$TMP/project"
mkdir -p "$repo/src" "$repo/docs" "$repo/node_modules/@scope/pkg"
git init -q -b main "$repo"
for i in 1 2 3 4 5 6 7 8 9 10; do printf 'line %d\n' "$i"; done > "$repo/src/app.ts"
printf 'all:\n\techo hi\n\n' > "$repo/Makefile"
printf 'one\ntwo\nthree\nfour\nfive' > "$repo/docs/a.md" # no newline at the end
printf 'export {}\n' > "$repo/node_modules/@scope/pkg/index.js"
printf '{}\n' > "$repo/package.json"
printf 'secret\n' > "$TMP/outside.ts"
report="$TMP/report.md"

# cite [args...]: runs the script from the repo; stdout in $TMP/out,
# stderr in $TMP/err
cite() { (cd "$repo" && bash "$CITE" "$@") > "$TMP/out" 2> "$TMP/err"; }
status_is() {
  local want=$1
  shift
  cite "$@"
  [ "$?" -eq "$want" ]
}
says() { grep -qF -- "$1" "$TMP/err"; }
prints() { grep -qF -- "$1" "$TMP/out"; }
write() { printf '%s\n' "$@" > "$report"; }

# --- arguments
check "--help prints the comment block and no code" help_ok "$CITE"
check "no arguments: usage error" status_is 2
check "it prints the usage" says 'Usage'
check "three arguments: usage error" status_is 2 "$report" "$repo" extra
check "a missing report: error" status_is 2 "$TMP/no-report.md"
check "it names the report" says 'no-report.md'
write 'src/app.ts:1'
check "a root that is not a directory: error" status_is 2 "$report" "$TMP/nothing"

# --- citations that resolve
write '# Trace' \
  'F1-1: functional' \
  '  path: src/app.ts:1 -> `src/app.ts:10` -> (src/app.ts:3-7)' \
  '  gap: none, see src/app.ts:4:12 and ./Makefile:3, also docs/a.md:5.' \
  '  dependency: node_modules/@scope/pkg/index.js:1, package.json:1'
check "citations that resolve pass" status_is 0 "$report"
check "it says how many it checked" prints '8 citations'
check "nothing is reported on stderr" test ! -s "$TMP/err"
check "an explicit root works from elsewhere" status_is 0 "$report" "$repo"
in_src() { (cd "$repo/src" && bash "$CITE" "$report") > "$TMP/out" 2> "$TMP/err"; }
in_src
check "the root defaults to the top of the git work tree" test "$?" -eq 0
printf 'see src/app.ts:2\r\nand src/app.ts:3\r\n' > "$report"
check "a CRLF report passes" status_is 0 "$report"

# --- citations that do not resolve
write 'ok src/app.ts:2' 'bad src/app.ts:11'
check "a line beyond the end fails" status_is 1 "$report"
check "it names the citation" says 'src/app.ts:11'
check "it names the report line" says 'report.md:2'
check "it gives the file's length" says '10 lines'
refute "it does not name the good one" says 'src/app.ts:2:'
write 'src/app.ts:5-11'
check "a range past the end fails" status_is 1 "$report"
write 'src/app.ts:7-3'
check "a reversed range fails" status_is 1 "$report"
write 'src/app.ts:0'
check "line 0 fails" status_is 1 "$report"
write 'docs/a.md:6'
check "the line after a last line without a newline fails" status_is 1 "$report"
write 'src/missing.ts:1'
check "a missing file fails" status_is 1 "$report"
check "it says no such file" says 'no such file'
write 'docs/:1'
check "a directory fails" status_is 1 "$report"
write '../outside.ts:1'
check "a path outside the repository fails" status_is 1 "$report"
check "it says outside" says 'outside'
write 'src/app.ts:1' 'src/missing.ts:2' 'src/app.ts:99'
check "every bad citation is listed" status_is 1 "$report"
check "the missing file is named" says 'src/missing.ts:2'
check "the line past the end is named" says 'src/app.ts:99'

# --- text that is not a citation
write 'Run it on http://localhost:3000/export at 10:30.' \
  'The API at https://example.com:8080/a.ts:3 and 127.0.0.1:8080, localhost:3000.' \
  'scheme:src/app.ts:1 follows a colon' \
  'Only src/app.ts:2 is a citation.'
check "URLs, times, addresses and hosts are not citations" status_is 0 "$report"
check "exactly one citation is checked" prints '1 citation'
write 'A report that cites nothing.' 'localhost:3000'
check "a report without citations fails" status_is 1 "$report"
check "it says none were found" says 'no path:line'

finish
