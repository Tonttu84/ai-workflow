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

# clear_git_env: unsets every exported GIT_* variable, so a test that runs
# git is not steered by the hook or tool that started it (GIT_DIR,
# GIT_INDEX_FILE, GIT_EDITOR and the like point at the outer repository).
clear_git_env() {
  local v
  for v in $(compgen -e); do
    case $v in GIT_*) unset "$v" ;; esac
  done
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

# help_ok <script>: --help prints the whole leading comment block, without
# the shebang or any code after the block.
help_ok() {
  local out want
  out=$(bash "$1" --help) || return 1
  case $out in *'#!'* | *'set -'*) return 1 ;; esac
  case $out in *Usage:*) ;; *) return 1 ;; esac
  want=$(awk 'NR == 1 { next } /^#/ { n++; next } { exit } END { print n + 0 }' "$1")
  [ "$(printf '%s\n' "$out" | wc -l)" -eq "$want" ]
}
