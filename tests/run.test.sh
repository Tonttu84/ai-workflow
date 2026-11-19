#!/usr/bin/env bash
# Tests for tests/run.sh, the runner itself: a copy of it runs fixture
# test files in a throwaway folder. A failing, killed, lost or missing
# file fails the run, the output keeps the files' order, TEST_JOBS=1 runs
# one file at a time, and more jobs run files at the same time.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

# fixtures: a fresh folder with a copy of the runner and no test files
fixtures() {
  rm -rf "$TMP/fx"
  mkdir -p "$TMP/fx/tests"
  cp "$ROOT/tests/run.sh" "$TMP/fx/tests/run.sh"
}
# fixture <name> <body>: a test file in the fixture folder
fixture() { printf '%s\n' "$2" > "$TMP/fx/tests/$1.test.sh"; }
# runs [variable=value...]: runs the copy with those variables set;
# stdout in $TMP/out, stderr in $TMP/err, the exit status in $TMP/status
runs() {
  env "$@" bash "$TMP/fx/tests/run.sh" > "$TMP/out" 2> "$TMP/err"
  echo "$?" > "$TMP/status"
}
status() { [ "$(cat "$TMP/status")" = "$1" ]; }
said() { grep -qF -- "$1" "$TMP/out" "$TMP/err"; }
all_passed() { grep -qx 'all tests passed' "$TMP/out"; }

# --- all pass
fixtures
fixture a 'echo a: 1 passed, 0 failed'
fixture b 'echo b: 1 passed, 0 failed'
runs
check "files that pass: the run passes" status 0
check "it says all tests passed" all_passed
check "it prints each file's output, in order" test "$(cat "$TMP/out")" = "$(printf '%s\n' \
  'a: 1 passed, 0 failed' 'b: 1 passed, 0 failed' 'all tests passed')"

# --- a failing file
fixtures
fixture a 'echo a ran'
fixture b 'echo "FAIL: b broke" >&2; exit 1'
fixture c 'echo c ran'
for jobs in 1 3; do
  runs TEST_JOBS=$jobs
  check "a failing file fails the run (jobs $jobs)" status 1
  refute "it does not say all tests passed (failing, jobs $jobs)" all_passed
  check "it says some tests failed (jobs $jobs)" said 'some tests failed'
  check "it names the failing file (jobs $jobs)" said 'b.test.sh'
  check "it shows the file's own failure (jobs $jobs)" said 'FAIL: b broke'
  check "the files after it still run (jobs $jobs)" said 'c ran'
done

# --- a file killed by a signal
fixtures
fixture a 'echo a ran'
fixture b "echo b starts; kill -KILL \$\$"
for jobs in 1 2; do
  runs TEST_JOBS=$jobs
  check "a file killed by a signal fails the run (jobs $jobs)" status 1
  refute "it does not say all tests passed (killed, jobs $jobs)" all_passed
  check "it names the killed file (jobs $jobs)" said 'b.test.sh'
done

# --- a file that never starts: it is gone by the time its turn comes
fixtures
fixture a "rm -f \"\$(dirname \"\$0\")/b.test.sh\"; echo a ran"
fixture b 'echo b ran'
runs TEST_JOBS=1
check "a file that never starts fails the run" status 1
refute "it does not say all tests passed (never started)" all_passed
refute "the missing file did not run" said 'b ran'
check "it names the file that never started" said 'b.test.sh'

# --- a file whose result is lost: what runs it is killed
fixtures
fixture a 'echo a ran'
fixture b "kill -KILL \$PPID; sleep 2"
fixture c 'echo c ran'
for jobs in 1 3; do
  runs TEST_JOBS=$jobs
  check "a file whose result is lost fails the run (jobs $jobs)" status 1
  refute "it does not say all tests passed (lost, jobs $jobs)" all_passed
  check "it names the file with no result (jobs $jobs)" said 'b.test.sh'
  check "the files after it still run (lost, jobs $jobs)" said 'c ran'
done

# --- the output order is the files' order, each file's output in one
# piece, stdout and stderr together, however long each file takes
fixtures
fixture a 'echo a out; sleep 3; echo a err >&2; echo a end'
fixture b 'echo b out; sleep 1; echo b err >&2; echo b end'
fixture c 'echo c out; echo c err >&2; echo c end'
for jobs in 1 3; do
  runs TEST_JOBS=$jobs
  check "the files pass (order, jobs $jobs)" status 0
  check "the output keeps the files' order (jobs $jobs)" \
    test "$(cat "$TMP/out")" = "$(printf '%s\n' 'a out' 'a err' 'a end' \
      'b out' 'b err' 'b end' 'c out' 'c err' 'c end' 'all tests passed')"
  cp "$TMP/out" "$TMP/out.$jobs"
done
check "the output is the same with one job and with three" cmp -s "$TMP/out.1" "$TMP/out.3"

# --- TEST_JOBS=1 runs one file at a time. Each file holds a lock folder
# while it runs; finding it taken means two files ran at the same time.
fixtures
for f in a b c; do
  fixture "$f" "lock=\"\$(dirname \"\$0\")/../lock\"
mkdir \"\$lock\" 2> /dev/null || { echo 'two files at once'; exit 1; }
sleep 1
rmdir \"\$lock\""
done
runs TEST_JOBS=1
check "with TEST_JOBS=1 no two files run at once" status 0
check "and it passes (jobs 1)" all_passed

# --- more jobs run files at the same time: two files that each wait (up
# to 60 s) for the other to start pass only when they run together
fixtures
rendezvous() { # rendezvous <me> <other>
  fixture "$1" "here=\"\$(dirname \"\$0\")/..\"
: > \"\$here/$1.started\"
i=0
while [ ! -e \"\$here/$2.started\" ] && [ \"\$i\" -lt 600 ]; do sleep 0.1; i=\$((i + 1)); done
[ -e \"\$here/$2.started\" ] || { echo '$1 ran alone'; exit 1; }"
}
rendezvous a b
rendezvous b a
runs TEST_JOBS=2
check "with two jobs two files run at the same time" status 0
check "and it passes (jobs 2)" all_passed

# --- a bad job count is refused before anything runs; an empty one is
# the default
fixtures
fixture a 'echo a ran'
for bad in 0 -1 x 1.5 ' 2' 007; do
  runs TEST_JOBS="$bad"
  check "TEST_JOBS='$bad' is refused" status 2
  refute "and nothing runs (TEST_JOBS='$bad')" said 'a ran'
  check "it names TEST_JOBS ('$bad')" said 'TEST_JOBS'
done
runs TEST_JOBS=
check "an empty TEST_JOBS is the default" status 0

# --- no test files is not a pass
fixtures
runs
refute "a folder with no test files does not pass" status 0
refute "it does not say all tests passed (no files)" all_passed

finish
