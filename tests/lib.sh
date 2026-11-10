# Shared helpers for the shell tests. Source it; do not run it.
# shellcheck shell=bash

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export ROOT

passed=0
failed=0

pass() {
  passed=$((passed + 1))
}

fail() {
  failed=$((failed + 1))
  printf 'FAIL: %s\n' "$1" >&2
}

# check <description> <condition command...>
check() {
  local desc=$1
  shift
  if "$@"; then pass; else fail "$desc"; fi
}

# refute <description> <command...>: the command must fail
refute() {
  local desc=$1
  shift
  if "$@"; then fail "$desc"; else pass; fi
}

# A scratch directory removed when the test script exits.
make_tmp() {
  TMP=$(mktemp -d)
  trap 'rm -rf "$TMP"' EXIT
}

# Prints the summary and exits non-zero when anything failed.
finish() {
  printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$passed" "$failed"
  [ "$failed" -eq 0 ]
}
