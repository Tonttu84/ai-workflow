#!/usr/bin/env bash
# Runs every tests/*.test.sh and fails if any of them fails.
#
# Files run in parallel, TEST_JOBS at a time (default: the number of
# cores minus one, at least one; TEST_JOBS=1 runs them one after
# another). Each file's stdout and stderr are buffered and printed
# together, in the files' order, so the log reads the same whatever the
# job count. A file that fails, dies of a signal, never starts or leaves
# no result fails the run. TEST_TIMES=1 adds the job count and each
# file's time in seconds on stderr.
set -u
cd "$(dirname "$0")/.." || exit 1

# cores: the number of processors, 1 when nothing says
cores() {
  local n
  n=$(getconf _NPROCESSORS_ONLN 2> /dev/null || nproc 2> /dev/null || sysctl -n hw.ncpu 2> /dev/null)
  [[ $n =~ ^[1-9][0-9]*$ ]] || n=${NUMBER_OF_PROCESSORS:-1}
  [[ $n =~ ^[1-9][0-9]*$ ]] || n=1
  printf '%s\n' "$n"
}

# The default leaves one core free, so a run does not freeze the machine.
jobs=${TEST_JOBS:-}
if [ -z "$jobs" ]; then
  jobs=$(($(cores) - 1))
  [ "$jobs" -ge 1 ] || jobs=1
fi
if ! [[ $jobs =~ ^[1-9][0-9]{0,3}$ ]]; then
  echo "run.sh: TEST_JOBS must be a whole number from 1 to 9999, not '$jobs'" >&2
  exit 2
fi
[ "${TEST_TIMES:-}" != 1 ] || echo "run.sh: running $jobs files at a time" >&2

files=()
for t in tests/*.test.sh; do
  [ -e "$t" ] && files+=("$t")
done
if [ "${#files[@]}" -eq 0 ]; then
  echo "run.sh: no tests/*.test.sh to run" >&2
  echo "some tests failed" >&2
  exit 1
fi

out=$(mktemp -d) || exit 1
trap 'rm -rf "$out"' EXIT
trap 'exit 130' INT # until the files start; then stop() below
trap 'exit 143' TERM

# The runner waits on a FIFO that each finished file writes a line to,
# so it wakes as soon as one ends and starts no process while it waits:
# on Windows a fork costs tens of milliseconds and, under load, can fail.
# Without a FIFO it sleeps a second at a time.
fifo=
if mkfifo "$out/done" 2> /dev/null && exec 9<> "$out/done"; then fifo=1; fi
pause() { # pause: until a file ends, at most a second or so
  if [ -n "$fifo" ]; then read -r -t 1 -u 9 _; else sleep 1; fi
}

# Each file runs in the foreground of a subshell, so it gets signals as
# it did when the runner ran it itself; its PID goes to $out/<n>.pid. The
# subshell then writes the file's exit status to $out/<n>.status, whole
# or not at all (written aside and renamed), so a status file that exists
# can be read at once. A subshell killed before that leaves no status,
# and the file counts as failed.
pids=()
began=() # $SECONDS when each file started
ended=() # and when the runner first saw it finished
start() { # start <n>
  (
    # SC2016: the inner shell expands $$, $0 and $1.
    # shellcheck disable=SC2016
    bash -c 'echo "$$" > "$0"; exec bash "$1"' "$out/$1.pid" "${files[$1]}" \
      > "$out/$1.log" 2>&1 < /dev/null 9>&-
    echo "$?" > "$out/$1.part" && mv -f "$out/$1.part" "$out/$1.status"
    [ -z "$fifo" ] || echo "$1" >&9
  ) &
  pids[$1]=$!
  began[$1]=$SECONDS
}

# finished <n>: the file has a status, or what runs it is gone
finished() {
  if [ -e "$out/$1.status" ] || ! kill -0 "${pids[$1]}" 2> /dev/null; then
    [ -n "${ended[$1]:-}" ] || ended[$1]=$SECONDS
    return 0
  fi
  return 1
}

failed=()
# report <n>: prints the file's output and notes a failure
report() {
  local t=${files[$1]} rc=''
  [ -f "$out/$1.log" ] && cat "$out/$1.log"
  [ "${TEST_TIMES:-}" != 1 ] || echo "run.sh: $t took $((ended[$1] - began[$1])) s" >&2
  [ -f "$out/$1.status" ] && read -r rc < "$out/$1.status"
  if ! [[ $rc =~ ^[0-9]+$ ]]; then
    echo "run.sh: $t left no result: what ran it was killed" >&2
    failed+=("$t")
  elif [ "$rc" -ne 0 ]; then
    if [ "$rc" -gt 128 ] && [ "$rc" -le 192 ]; then
      echo "run.sh: $t was killed by signal $((rc - 128))" >&2
    fi
    failed+=("$t")
  fi
}

total=${#files[@]}
# The biggest files start first: the long ones then do not start last and
# leave the other jobs idle at the end. Output keeps the files' order.
order=()
while read -r _ name; do
  for ((i = 0; i < total; i++)); do
    [ "${files[$i]}" = "$name" ] && order+=("$i")
  done
done < <(wc -c "${files[@]}" | sed '$d' | sort -rn)
if [ "${#order[@]}" -ne "$total" ]; then # a name wc could not give back
  order=()
  for ((i = 0; i < total; i++)); do order+=("$i"); done
fi

next=0    # the next place in $order to start
printed=0 # the next file to print

# summary: the verdict of the whole run; fails when any file failed
summary() {
  if [ "${#failed[@]}" -eq 0 ]; then
    echo "all tests passed"
  else
    printf 'failed: %s\n' "${failed[@]}" >&2
    echo "some tests failed" >&2
    return 1
  fi
}

# stop <exit status> <signal>: on INT or TERM, stops the files still
# running (what runs each first, so it writes nothing after the runner
# has gone), prints what the rest left, names the files that did not
# finish or start, and exits
stop() {
  local i p t running=()
  trap '' INT TERM
  for ((i = printed; i < total; i++)); do
    [ -n "${pids[$i]:-}" ] && ! finished "$i" && running[i]=1
  done
  for i in "${!running[@]}"; do
    kill -TERM "${pids[$i]}" 2> /dev/null
    p=
    [ -f "$out/$i.pid" ] && read -r p < "$out/$i.pid"
    [ -z "$p" ] || kill -TERM "$p" 2> /dev/null
  done
  echo "run.sh: stopped by $2" >&2
  for ((i = printed; i < total; i++)); do
    t=${files[$i]}
    if [ -z "${pids[$i]:-}" ]; then
      echo "run.sh: $t did not start" >&2
      failed+=("$t")
    elif [ -n "${running[$i]:-}" ]; then
      echo "run.sh: $t did not finish; the last lines of its output:" >&2
      tail -n 20 "$out/$i.log" >&2 2> /dev/null
      failed+=("$t")
    else
      report "$i"
    fi
  done
  summary
  exit "$1"
}
trap 'stop 130 INT' INT
trap 'stop 143 TERM' TERM

while [ "$printed" -lt "$total" ]; do
  running=0
  for ((i = 0; i < total; i++)); do
    [ -n "${pids[$i]:-}" ] && ! finished "$i" && running=$((running + 1))
  done
  while [ "$running" -lt "$jobs" ] && [ "$next" -lt "$total" ]; do
    start "${order[$next]}"
    next=$((next + 1))
    running=$((running + 1))
  done
  # Print, in order, every file that has finished; the rest wait.
  while [ "$printed" -lt "$total" ] && [ -n "${pids[$printed]:-}" ] && finished "$printed"; do
    report "$printed"
    printed=$((printed + 1))
  done
  [ "$printed" -ge "$total" ] || pause
done
summary
