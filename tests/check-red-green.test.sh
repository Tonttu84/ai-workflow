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

finish
