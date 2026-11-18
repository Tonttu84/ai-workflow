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
mkdir -p "$repo/src" "$repo/docs" "$repo/vendor/@scope/pkg"
git init -q -b main "$repo"
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.com
git -C "$repo" config core.autocrlf false
for i in 1 2 3 4 5 6 7 8 9 10; do printf 'line %d\n' "$i"; done > "$repo/src/app.ts"
printf 'all:\n\techo hi\n\n' > "$repo/Makefile"
printf 'one\ntwo\nthree\nfour\nfive' > "$repo/docs/a.md" # no newline at the end
printf 'export {}\n' > "$repo/vendor/@scope/pkg/index.js"
printf '{}\n' > "$repo/package.json"
printf 'node_modules/\n' > "$repo/.gitignore"
git -C "$repo" add -A
git -C "$repo" commit -q -m "feat: start"
first=$(git -C "$repo" rev-parse HEAD)
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
# SC2016: the backticks are Markdown in the trace report.
# shellcheck disable=SC2016
write '# Trace' \
  'F1-1: functional' \
  '  path: src/app.ts:1 -> `src/app.ts:10` -> (src/app.ts:3-7)' \
  '  gap: none, see src/app.ts:4:12 and ./Makefile:3, also docs/a.md:5.' \
  '  dependency: vendor/@scope/pkg/index.js:1, package.json:1'
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
write 'exists: src/app.ts:99999999999999999999'
check "a line number too big for an integer fails" status_is 1 "$report"
check "it names the citation" says 'src/app.ts:99999999999999999999'
write 'src/app.ts:1-99999999999999999999'
check "a range end too big for an integer fails" status_is 1 "$report"
write 'src/app.ts:00000000000000000000000000001'
check "a line number with many leading zeros is still read as its value" status_is 0 "$report"
write 'see .git/config:1'
check "a file inside .git fails" status_is 1 "$report"
check "it says it is inside .git" says '.git'
for git_dir in .GIT .Git src/.GiT; do
  write "see $git_dir/config:1"
  check "a file inside $git_dir fails" status_is 1 "$report"
done

# --- only files committed at the revision count (HEAD by default): an
# untracked or ignored file is not what the report's commit holds
mkdir -p "$repo/node_modules/x"
printf 'a\nb\n' > "$repo/node_modules/x/index.js"
write 'node_modules/x/index.js:2'
check "an ignored file fails" status_is 1 "$report"
check "it says only committed files count" says 'only committed files count'
printf 'a\nb\n' > "$repo/src/new.ts"
write 'src/new.ts:1'
check "an untracked file fails" status_is 1 "$report"
git -C "$repo" add src/new.ts
check "a staged file that is not committed fails" status_is 1 "$report"
git -C "$repo" rm -q --cached src/new.ts
rm "$repo/src/new.ts"
printf 'extra\n' >> "$repo/src/app.ts"
write 'src/app.ts:11'
check "a line added only in the working tree fails" status_is 1 "$report"
git -C "$repo" commit -q -am "feat: one more line"
check "committed, it resolves" status_is 0 "$report"
check "--rev reads another commit: there the line is beyond the end" status_is 1 --rev "$first" "$report"
check "it gives that commit's length" says '10 lines'
write 'src/app.ts:10'
check "--rev with a line the commit has passes" status_is 0 --rev "$first" "$report"
check "--rev with an explicit root" status_is 0 --rev "$first" "$report" "$repo"
check "--rev with an unknown commit: error" status_is 2 --rev no-such-ref "$report"
check "--rev without a value: usage error" status_is 2 --rev
ln -s app.ts "$repo/src/link.ts" 2> /dev/null &&
  git -C "$repo" add src/link.ts && git -C "$repo" commit -q -m "chore: a link" &&
  if [ "$(git -C "$repo" ls-files -s src/link.ts | cut -c1-6)" = 120000 ]; then
    write 'src/link.ts:1'
    check "a symbolic link is not a file" status_is 1 "$report"
  fi
mkdir -p "$TMP/no-git"
no_git() { (cd "$TMP/no-git" && GIT_CEILING_DIRECTORIES="$TMP" bash "$CITE" "$report" "$TMP/no-git") > "$TMP/out" 2> "$TMP/err"; }
no_git
check "a root outside any git work tree: error" test "$?" -eq 2
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
