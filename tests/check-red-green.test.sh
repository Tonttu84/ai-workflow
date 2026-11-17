#!/usr/bin/env bash
# Tests for scripts/check-red-green.sh: each locked test must fail on the
# code before the feature and pass on the code with it. A throwaway repo
# and a fake test runner stand in for a project and its test framework.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp
clear_git_env # the tests run git; an outer hook's GIT_* must not steer it

RG="$ROOT/scripts/check-red-green.sh"

# The script's temporary worktrees go under $TMP/scratch, so a test can
# see that nothing is left behind.
scratch="$TMP/scratch"
mkdir -p "$scratch"

repo="$TMP/project"
git init -q -b main "$repo"
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.com
git -C "$repo" config core.autocrlf false
mkdir -p "$repo/e2e" "$repo/src"
# The fake runner: runs every *.test.sh under the paths it is given and
# fails when any of them fails, or when there is none.
cat > "$repo/run-tests.sh" << 'EOF'
found=0
for p in "$@"; do
  while IFS= read -r t; do
    found=1
    bash "$t" < /dev/null || exit 1
  done < <(find "$p" -name '*.test.sh' | sort)
done
[ "$found" -eq 1 ]
EOF
printf 'echo ""\n' > "$repo/src/greet.sh"
git -C "$repo" add -A
git -C "$repo" commit -q -m "feat: start"
before=$(git -C "$repo" rev-parse HEAD)

# Each test finds the code from its own place, so it runs from anywhere.
# SC2016: the tests are shell text, written out unexpanded.
# shellcheck disable=SC2016
greet_test() { # greet_test <file> <expected greeting>
  printf 'here=$(dirname "$0")\n[ "$(bash "$here/../src/greet.sh")" = %s ]\n' "$2" > "$1"
}
greet_test "$repo/e2e/one.test.sh" hello
greet_test "$repo/e2e/two words.test.sh" hello
git -C "$repo" add -A
git -C "$repo" commit -q -m "test: lock the tests for greeting"
locked=$(git -C "$repo" rev-parse HEAD)
printf 'echo hello\n' > "$repo/src/greet.sh"
git -C "$repo" commit -q -am "feat: greet"
head=$(git -C "$repo" rev-parse HEAD)

CMD='bash run-tests.sh {path}'
# rg [args...]: runs the script in the repo; stdout in $TMP/out, stderr in
# $TMP/err
rg() { (cd "$repo" && TMPDIR="$scratch" bash "$RG" "$@") > "$TMP/out" 2> "$TMP/err"; }
status_is() {
  local want=$1
  shift
  rg "$@"
  [ "$?" -eq "$want" ]
}
says() { grep -qF -- "$1" "$TMP/err"; }
prints() { grep -qF -- "$1" "$TMP/out"; }
# clean: no temporary worktree is registered and nothing is left on disk
clean() {
  [ "$(git -C "$repo" worktree list | wc -l)" -eq 1 ] && [ -z "$(ls -A "$scratch")" ]
}
reset_repo() {
  git -C "$repo" reset -q --hard "$head" && git -C "$repo" clean -qfdx
  rm -rf "${scratch:?}"/*
}

# --- arguments
check "--help prints the comment block and no code" help_ok "$RG"
check "no arguments: usage error" status_is 2
check "it prints the usage" says 'Usage'
check "a base and a command but no path: usage error" status_is 2 "$before" "$CMD"
check "an unknown base: error" status_is 2 1234567890123456789012345678901234567890 "$CMD" e2e/one.test.sh
check "it names the base" says 1234567890123456789012345678901234567890
check "a command without {path}: error" status_is 2 "$before" 'bash run-tests.sh' e2e/one.test.sh
check "it says {path} is missing" says '{path}'
check "a missing path: error" status_is 2 "$before" "$CMD" e2e/missing.test.sh
check "it names the path" says e2e/missing.test.sh
check "an empty path: error" status_is 2 "$before" "$CMD" ""
check "a timeout that is not whole seconds: error" status_is 2 --timeout 1.5 "$before" "$CMD" e2e/one.test.sh
check "it names the timeout" says 1.5
check "a zero timeout: error" status_is 2 --timeout 0 "$before" "$CMD" e2e/one.test.sh
check "an unknown option: error" status_is 2 --bogus "$before" "$CMD" e2e/one.test.sh
outside() { (cd "$TMP" && TMPDIR="$scratch" bash "$RG" "$before" "$CMD" e2e/one.test.sh) > "$TMP/out" 2>&1; }
outside
check "outside a git work tree: error" test "$?" -eq 2
check "argument errors leave nothing behind" clean

# --- red on the base, green on the head
check "tests that fail before the feature and pass with it pass" \
  status_is 0 "$before" "$CMD" e2e/one.test.sh "e2e/two words.test.sh"
check "it reports the first path" prints 'e2e/one.test.sh'
check "it reports the path with a space" prints 'e2e/two words.test.sh'
check "nothing is reported on stderr" test ! -s "$TMP/err"
check "the temporary worktree is removed" clean
check "a locked directory passes" status_is 0 "$before" "$CMD" e2e
check "the test: commit works as the base" status_is 0 "$locked" "$CMD" e2e
check "a short SHA works as the base" status_is 0 "$(git -C "$repo" rev-parse --short "$before")" "$CMD" e2e
check "the working tree is left as it was" test -z "$(git -C "$repo" status --porcelain)"

from_e2e() { (cd "$repo/e2e" && TMPDIR="$scratch" bash "$RG" "$before" 'bash ../run-tests.sh {path}' one.test.sh) > "$TMP/out" 2> "$TMP/err"; }
from_e2e
check "from a subdirectory, paths and the command are relative to it" test "$?" -eq 0

# --- a test that passes on the base does not need the feature
printf 'true\n' > "$repo/e2e/vacuous.test.sh"
check "a test that passes on the base fails" status_is 1 "$before" "$CMD" e2e/vacuous.test.sh
check "it names the test" says 'e2e/vacuous.test.sh'
check "it says it passed on the base" says 'passes on the base'
check "it is cleaned up after a failure" clean
check "one vacuous test among failing ones is still found" \
  status_is 1 "$before" "$CMD" e2e/one.test.sh e2e/vacuous.test.sh
check "only the vacuous test is named" test "$(grep -c 'e2e/' "$TMP/err")" -eq 1
check "an untracked test is copied to the base" status_is 1 "$before" "$CMD" e2e/vacuous.test.sh
reset_repo

# --- a locked directory runs each test file in it on its own
printf 'true\n' > "$repo/e2e/vacuous.test.sh"
git -C "$repo" add -A
git -C "$repo" commit -q -m "test: add a vacuous test"
check "a vacuous test inside a locked directory is not hidden by a failing one" \
  status_is 1 "$before" "$CMD" e2e
check "it names the vacuous file" says 'e2e/vacuous.test.sh'
check "it says it passed on the base" says 'passes on the base'
check "the other files are reported on their own" prints 'e2e/one.test.sh: base failed, head passed'
reset_repo

# A file in a locked directory that is not a test (a helper the tests
# use) is copied to the base but not run on its own.
# shellcheck disable=SC2016
printf 'expected=hello\n' > "$repo/e2e/helper.sh"
printf 'here=$(dirname "$0")\n. "$here/helper.sh" || exit 1\n[ "$(bash "$here/../src/greet.sh")" = "$expected" ]\n' \
  > "$repo/e2e/uses-helper.test.sh"
git -C "$repo" add -A
git -C "$repo" commit -q -m "test: share a helper"
check "a helper in a locked directory is copied but not run" status_is 0 "$before" "$CMD" e2e
refute "the helper is not reported as a test" prints 'e2e/helper.sh'
check "the test that sources it ran on both sides" prints 'e2e/uses-helper.test.sh: base failed, head passed'
check "--match picks the test files in a directory" \
  status_is 0 --match 'uses-*.sh' "$before" "$CMD" e2e
check "only the matching file ran" test "$(grep -c ': base' "$TMP/out")" -eq 1
check "a directory with no file that matches: error" \
  status_is 2 --match '*.nothing' "$before" "$CMD" e2e
check "it says no test file matched" says 'no test file'
check "a file given by name runs whatever its name" status_is 0 --match '*.nothing' "$before" "$CMD" e2e/uses-helper.test.sh
reset_repo

# --- a locked path git does not track and would not track is an error,
# not a red: the base would lack it and the run there would fail
mkdir -p "$repo/e2e/ignored"
printf 'e2e/ignored/\n' > "$repo/.gitignore"
git -C "$repo" add .gitignore
git -C "$repo" commit -q -m "chore: ignore a directory"
printf 'true\n' > "$repo/e2e/ignored/vacuous.test.sh"
check "a locked path whose files git ignores: error" status_is 2 "$before" "$CMD" e2e/ignored
check "it says git tracks nothing there" says 'no files git tracks'
reset_repo

# --- a test file deleted in the working tree is not copied or run
rm "$repo/e2e/two words.test.sh"
rg "$before" "$CMD" e2e
check "the other files in the directory still run" prints 'e2e/one.test.sh: base failed, head passed'
refute "the deleted file is not copied" says 'cannot stat'
reset_repo

# --- the head side runs in the working tree, so the working tree must be
# HEAD, the commit that gets pushed: code that is not committed would make
# "passes on the head" true for code nobody pushes
# shellcheck disable=SC2016
printf 'here=$(dirname "$0")\n[ "$(bash "$here/../src/extra.sh")" = extra ]\n' > "$repo/e2e/extra.test.sh"
git -C "$repo" add e2e/extra.test.sh
git -C "$repo" commit -q -m "test: lock the extra test"
printf 'echo extra\n' > "$repo/src/extra.sh" # never added
check "code the head needs that was never added fails" status_is 1 "$before" "$CMD" e2e/extra.test.sh
check "it says the working tree is not HEAD" says 'not HEAD'
check "it counts the untracked file" says '1 untracked'
printf 'src/extra.sh\n' >> "$repo/.git/info/exclude"
check "the same file hidden by .git/info/exclude still fails" status_is 1 "$before" "$CMD" e2e/extra.test.sh
check "it is still counted" says '1 untracked'
: > "$repo/.git/info/exclude"
git -C "$repo" add src/extra.sh
check "the same file staged but not committed fails" status_is 1 "$before" "$CMD" e2e/extra.test.sh
check "it counts the changed file" says '1 changed'
git -C "$repo" commit -q -m "feat: extra"
check "committed, it passes" status_is 0 "$before" "$CMD" e2e/extra.test.sh
printf 'echo other\n' > "$repo/src/extra.sh"
git -C "$repo" update-index --skip-worktree src/extra.sh
check "a change hidden by skip-worktree fails" status_is 1 "$before" "$CMD" e2e/extra.test.sh
check "it counts the flagged file" says '1 flagged'
git -C "$repo" update-index --no-skip-worktree src/extra.sh
git -C "$repo" checkout -q -- src/extra.sh
printf 'echo other\n' > "$repo/src/extra.sh"
git -C "$repo" update-index --assume-unchanged src/extra.sh
check "a change hidden by assume-unchanged fails" status_is 1 "$before" "$CMD" e2e/extra.test.sh
check "it counts the file as flagged" says '1 flagged'
git -C "$repo" update-index --no-assume-unchanged src/extra.sh
git -C "$repo" checkout -q -- src/extra.sh
printf 'build/\n' > "$repo/.gitignore"
git -C "$repo" add .gitignore
git -C "$repo" commit -q -m "chore: ignore the build"
mkdir -p "$repo/build"
printf 'built\n' > "$repo/build/out.txt"
check "files the committed .gitignore ignores do not count" status_is 0 "$before" "$CMD" e2e/extra.test.sh
reset_repo

# An untracked .gitignore that ignores itself hides what is next to it
# from git: here a helper that makes the locked test pass on the head.
# Only committed .gitignore files may hide a file, so one in or above a
# locked path fails.
# shellcheck disable=SC2016
printf 'here=$(dirname "$0")\n[ "$(bash "$here/../src/greet.sh")" = nope ] || [ -f "$here/conftest.sh" ]\n' \
  > "$repo/e2e/hidden.test.sh"
git -C "$repo" add e2e/hidden.test.sh
git -C "$repo" commit -q -m "test: lock a test a hidden helper passes"
printf '*\n' > "$repo/e2e/.gitignore"
printf 'skip\n' > "$repo/e2e/conftest.sh"
check "git status shows nothing" test -z "$(git -C "$repo" status --porcelain)"
check "an untracked .gitignore in a locked directory fails" status_is 1 "$before" "$CMD" e2e
check "it counts the .gitignore" says '1 untracked .gitignore'
check "an untracked .gitignore above a locked file fails" status_is 1 "$before" "$CMD" e2e/hidden.test.sh
rm "$repo/e2e/.gitignore" "$repo/e2e/conftest.sh"
mkdir -p "$repo/e2e/deep"
printf '*\n' > "$repo/e2e/deep/.gitignore"
printf 'skip\n' > "$repo/e2e/deep/conftest.sh"
check "one deeper in a locked directory fails too" status_is 1 "$before" "$CMD" e2e
check "it counts the deeper .gitignore" says '1 untracked .gitignore'
rm -r "$repo/e2e/deep"
# The walk goes up past the locked path's own directory to the top.
printf '*\n' > "$repo/.gitignore"
printf 'skip\n' > "$repo/e2e/conftest.sh"
check "git status shows nothing (a .gitignore at the top)" test -z "$(git -C "$repo" status --porcelain)"
check "an untracked .gitignore at the top fails" status_is 1 "$before" "$CMD" e2e/hidden.test.sh
check "it counts the .gitignore at the top" says '1 untracked .gitignore'
rm "$repo/.gitignore" "$repo/e2e/conftest.sh"
# git on a case-insensitive file system (Windows, macOS) reads
# .GITIGNORE as the folder's .gitignore, so the name is compared without
# regard to case. On a case-sensitive one the helper is not hidden and
# the check fails all the same.
printf '*\n' > "$repo/e2e/.GITIGNORE"
printf 'skip\n' > "$repo/e2e/conftest.sh"
check "an untracked upper-case .GITIGNORE in a locked directory fails" status_is 1 "$before" "$CMD" e2e
check "it counts the upper-case .GITIGNORE" says '1 untracked .gitignore'
check "an untracked upper-case .GITIGNORE above a locked file fails" status_is 1 "$before" "$CMD" e2e/hidden.test.sh
rm "$repo/e2e/.GITIGNORE" "$repo/e2e/conftest.sh"
mkdir -p "$repo/e2e/deep"
printf '*\n' > "$repo/e2e/deep/.GitIgnore"
check "a mixed-case .GitIgnore deeper in a locked directory fails" status_is 1 "$before" "$CMD" e2e
check "it counts the mixed-case .GitIgnore" says '1 untracked .gitignore'
rm -r "$repo/e2e/deep"
printf '*\n' > "$repo/.GITIGNORE"
printf 'skip\n' > "$repo/e2e/conftest.sh"
check "an untracked upper-case .GITIGNORE at the top fails" status_is 1 "$before" "$CMD" e2e/hidden.test.sh
rm "$repo/.GITIGNORE" "$repo/e2e/conftest.sh"
# Test tools write such files into their caches (.pytest_cache,
# .ruff_cache, a Python 3.13 .venv); outside the locked paths they do
# not count.
mkdir -p "$repo/.pytest_cache"
printf '*\n' > "$repo/.pytest_cache/.gitignore"
check "a self-ignoring cache directory outside the locked paths passes" status_is 0 "$before" "$CMD" e2e/one.test.sh
reset_repo

# --- a test that fails on the head
greet_test "$repo/e2e/wrong.test.sh" goodbye
check "a test that fails on the head fails" status_is 1 "$before" "$CMD" e2e/wrong.test.sh
check "it names the test" says 'e2e/wrong.test.sh'
check "it says it fails on the head" says 'fails on the head'
reset_repo

printf 'echo ""\n' > "$repo/src/greet.sh"
check "the head is the working tree: an uncommitted break fails" status_is 1 "$before" "$CMD" e2e/one.test.sh
check "it says the head fails" says 'fails on the head'
reset_repo

# --- the locked tests come from the working tree, not from the base
printf 'true\n' > "$repo/e2e/one.test.sh"
check "a locked test weakened in the working tree is the one run on the base" \
  status_is 1 "$before" "$CMD" e2e/one.test.sh
reset_repo

# --- time limits: a run that hangs is not a pass or a fail
# shellcheck disable=SC2016
printf 'here=$(dirname "$0")\n[ -n "$(bash "$here/../src/greet.sh")" ] || sleep 30\n' > "$repo/e2e/slow.test.sh"
check "a test that hangs on the base fails the check" status_is 1 --timeout 2 "$before" "$CMD" e2e/slow.test.sh
check "it says it timed out" says 'timed out'
check "it says where" says 'on the base'
check "the hung run is cleaned up" clean
reset_repo

# A test that ignores SIGTERM (run directly, so nothing between timeout
# and it dies of the signal) is killed with SIGKILL after the grace
# period: timeout then exits 137, not 124, and that is a hang too.
# shellcheck disable=SC2016
printf 'trap "" TERM\nhere=$(dirname "$0")\n[ -n "$(bash "$here/../src/greet.sh")" ] || while :; do sleep 1; done\n' \
  > "$repo/e2e/stubborn.test.sh"
check "a test that ignores SIGTERM and hangs on the base fails the check" \
  status_is 1 --timeout 1 "$before" 'bash {path}' e2e/stubborn.test.sh
check "it says it timed out" says 'timed out'
refute "it is not taken for a red" prints 'base failed'
check "the killed run is cleaned up" clean
reset_repo

# --- the setup command runs in the temporary worktree first
# shellcheck disable=SC2016
printf 'here=$(dirname "$0")\n[ -f "$here/../.deps" ]\n' > "$repo/e2e/deps.test.sh"
touch "$repo/.deps"
check "a test that only needs installed dependencies passes on the base with setup" \
  status_is 1 --setup 'touch .deps' "$before" "$CMD" e2e/deps.test.sh
check "it is named" says 'e2e/deps.test.sh'
check "a failing setup is an error" status_is 2 --setup 'exit 3' "$before" "$CMD" e2e/one.test.sh
check "it says the setup failed" says 'setup'
check "a failed setup is cleaned up" clean
check "a setup that hangs is an error" status_is 2 --timeout 2 --setup 'sleep 30' "$before" "$CMD" e2e/one.test.sh
reset_repo

# --- a command that cannot run is a setup error, not a red
check "a command that is not found is an error" \
  status_is 2 "$before" 'no-such-command-for-check-red-green {path}' e2e/one.test.sh
check "it names the exit status" says '127'
check "it is cleaned up" clean
check "a command that cannot be run (126) is an error" status_is 2 "$before" 'exit 126; {path}' e2e/one.test.sh
check "it names that exit status" says '126'

# --- the guard against untracked .gitignore files is one function, kept
# word for word in check-red-green.sh and check-locked-tests.sh (each
# script installs on its own), with its comment
ignores_function() { awk '/^# untracked_ignores / { on = 1 } on { print } on && /^}$/ { exit }' "$1"; }
check "check-red-green.sh has untracked_ignores" test -n "$(ignores_function "$RG")"
check "check-locked-tests.sh holds the same untracked_ignores, word for word" \
  test "$(ignores_function "$RG")" = "$(ignores_function "$ROOT/scripts/check-locked-tests.sh")"

finish
