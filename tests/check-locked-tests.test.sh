#!/usr/bin/env bash
# Tests for scripts/check-locked-tests.sh: the tests a test writer locked
# in a commit must be the same in the working tree and the index, whether
# a change to them was committed or not.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp
clear_git_env # the tests run git; an outer hook's GIT_* must not steer it

LOCK="$ROOT/scripts/check-locked-tests.sh"

repo="$TMP/project"
git init -q -b main "$repo"
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.com
git -C "$repo" config core.autocrlf false
mkdir -p "$repo/e2e" "$repo/src"
printf 'test one\n' > "$repo/e2e/one.test.sh"
printf 'test two\n' > "$repo/e2e/two words.test.sh"
printf 'code\n' > "$repo/src/app.sh"
git -C "$repo" add -A
git -C "$repo" commit -q -m "test: lock the feature's tests"
base=$(git -C "$repo" rev-parse HEAD)

# locked [args...]: runs the script in the repo; its output goes to $TMP/out
locked() { (cd "$repo" && bash "$LOCK" "$@") > "$TMP/out" 2>&1; }
# status_is <status> [args...]: the script exits with that status
status_is() {
  local want=$1
  shift
  locked "$@"
  [ "$?" -eq "$want" ]
}
says() { grep -qF -- "$1" "$TMP/out"; }
reset_repo() { git -C "$repo" reset -q --hard "$base" && git -C "$repo" clean -qfd; }
commit_all() { git -C "$repo" add -A && git -C "$repo" commit -q -m "$1"; }

# --- arguments
check "--help prints the comment block and no code" help_ok "$LOCK"
check "no arguments: usage error" status_is 2
check "it prints the usage" says 'Usage'
check "a base and no path: usage error" status_is 2 "$base"
check "an unknown base: error" status_is 2 1234567890123456789012345678901234567890 e2e/one.test.sh
check "it names the base" says 1234567890123456789012345678901234567890
check "an empty path: error" status_is 2 "$base" ""
check "it says the path is empty" says 'empty path'
check "a path the base does not have: error" status_is 2 "$base" e2e/missing.test.sh
check "it names the path" says e2e/missing.test.sh
outside() { (cd "$TMP" && bash "$LOCK" "$base" e2e/one.test.sh) > "$TMP/out" 2>&1; }
outside
check "outside a git work tree: error" test "$?" -eq 2

# --- unchanged
check "unchanged files pass" status_is 0 "$base" e2e/one.test.sh "e2e/two words.test.sh"
check "an unchanged directory passes" status_is 0 "$base" e2e
check "a short SHA works as the base" status_is 0 "$(git -C "$repo" rev-parse --short "$base")" e2e
printf 'more code\n' >> "$repo/src/app.sh"
commit_all "feat: build the feature"
check "a change to other files passes" status_is 0 "$base" e2e
reset_repo

# --- changed, committed or not
printf 'weakened\n' >> "$repo/e2e/one.test.sh"
commit_all "fix: adjust a test"
check "a committed change fails" status_is 1 "$base" e2e/one.test.sh "e2e/two words.test.sh"
check "it names the changed file" says e2e/one.test.sh
refute "it does not name the unchanged one" says 'two words'
reset_repo

printf 'weakened\n' >> "$repo/e2e/one.test.sh"
check "an uncommitted change fails" status_is 1 "$base" e2e/one.test.sh
check "it names the file" says e2e/one.test.sh
reset_repo

printf 'weakened\n' >> "$repo/e2e/one.test.sh"
git -C "$repo" add e2e/one.test.sh
printf 'test one\n' > "$repo/e2e/one.test.sh"
check "a staged change undone in the working tree still fails" status_is 1 "$base" e2e/one.test.sh
reset_repo

printf 'weakened\n' >> "$repo/e2e/one.test.sh"
git -C "$repo" add e2e/one.test.sh
printf 'weakened again\n' >> "$repo/e2e/one.test.sh"
check "a file changed in the index and the working tree fails" status_is 1 "$base" e2e/one.test.sh
check "it is named once" test "$(grep -c 'e2e/one.test.sh' "$TMP/out")" -eq 1
reset_repo

printf 'weakened\n' >> "$repo/e2e/one.test.sh"
printf 'weakened\n' >> "$repo/e2e/two words.test.sh"
check "two changed files fail" status_is 1 "$base" e2e/one.test.sh "e2e/two words.test.sh"
check "it names the first" says e2e/one.test.sh
check "it names the second, spaces and all" says 'e2e/two words.test.sh'
reset_repo

printf 'weakened\n' >> "$repo/e2e/one.test.sh"
commit_all "fix: adjust a test"
git -C "$repo" checkout -q "$base" -- e2e/one.test.sh
commit_all "revert: put the test back"
check "a change put back passes" status_is 0 "$base" e2e/one.test.sh
reset_repo

# --- deleted
git -C "$repo" rm -q e2e/one.test.sh
commit_all "test: drop a test"
check "a committed deletion fails" status_is 1 "$base" e2e/one.test.sh
check "it says the file was deleted" says 'deleted: e2e/one.test.sh'
reset_repo

rm "$repo/e2e/one.test.sh"
check "an uncommitted deletion fails" status_is 1 "$base" e2e/one.test.sh
check "it says so" says 'deleted: e2e/one.test.sh'
reset_repo

git -C "$repo" mv e2e/one.test.sh e2e/renamed.test.sh
commit_all "test: rename a test"
check "a renamed file in a locked directory fails" status_is 1 "$base" e2e
check "the old name is reported deleted" says 'deleted: e2e/one.test.sh'
check "the new name is reported added" says 'added: e2e/renamed.test.sh'
reset_repo

git -C "$repo" rm -q --cached e2e/one.test.sh
check "a file taken out of git but left on disk fails" status_is 1 "$base" e2e/one.test.sh
reset_repo

# --- a locked directory: changed, deleted and new files inside it
printf 'weakened\n' >> "$repo/e2e/one.test.sh"
check "a change inside a locked directory fails" status_is 1 "$base" e2e
check "it names the file inside" says e2e/one.test.sh
reset_repo

printf 'skip everything\n' > "$repo/e2e/conftest.sh"
check "a new untracked file in a locked directory fails" status_is 1 "$base" e2e
check "it says the file was added" says 'added: e2e/conftest.sh'
commit_all "test: add a helper"
check "the same file committed fails" status_is 1 "$base" e2e
reset_repo

# --- paths are relative to where it runs, as git's are
in_e2e() { (cd "$repo/e2e" && bash "$LOCK" "$base" one.test.sh) > "$TMP/out" 2>&1; }
in_e2e
check "from a subdirectory: an unchanged file passes" test "$?" -eq 0
printf 'weakened\n' >> "$repo/e2e/one.test.sh"
in_e2e
check "from a subdirectory: a changed file fails" test "$?" -eq 1
reset_repo

# --- line endings: a Windows checkout of an unchanged file passes
git -C "$repo" config core.autocrlf true
printf 'test one\r\n' > "$repo/e2e/one.test.sh"
check "a CRLF checkout under core.autocrlf passes" status_is 0 "$base" e2e/one.test.sh
git -C "$repo" config core.autocrlf false
reset_repo

finish
