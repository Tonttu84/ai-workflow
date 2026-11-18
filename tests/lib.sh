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

# local_skills [<skills dir>]: the skills that are this repo's own, not
# synced from upstream (the dir's UPSTREAM file lists the synced ones),
# one name per line. The dir defaults to $ROOT/skills.
local_skills() {
  local skills=${1:-$ROOT/skills} dir name synced
  synced=" $(sed -n 's/^skills: //p' "$skills/UPSTREAM") "
  for dir in "$skills"/*/; do
    dir=${dir%/}
    name=$(basename "$dir")
    [ -f "$dir/SKILL.md" ] || continue
    case $synced in *" $name "*) continue ;; esac
    printf '%s\n' "$name"
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

# --- the workflow templates (templates/*.yml)

# count <text> <file>: the number of lines that hold the text
count() { grep -c -- "$1" "$2"; }

# hardened <workflow>: every action is pinned by a full SHA, every
# checkout keeps no credentials, every job has a timeout, the token is
# read-only, and no ${{ }} expression is pasted into a run script
hardened() {
  local uses
  uses=$(count 'uses: ' "$1")
  [ "$uses" -gt 0 ] &&
    [ "$(grep -cE 'uses: [^@ ]+@[0-9a-f]{40}( |$)' "$1")" -eq "$uses" ] &&
    [ "$(count 'persist-credentials: false' "$1")" -eq "$(count 'uses: actions/checkout@' "$1")" ] &&
    [ "$(count 'timeout-minutes: ' "$1")" -eq "$(count 'runs-on: ' "$1")" ] &&
    grep -qx 'permissions:' "$1" && grep -qx '  contents: read' "$1" &&
    ! awk '
      /^ *run: \|/ { indent = index($0, "r"); inrun = 1; next }
      inrun && NF && index($0, substr($0, 1, indent - 1) " ") != 1 { inrun = 0 }
      inrun && /\$\{\{/ { bad = 1 }
      /^ *run: [^|]/ && /\$\{\{/ { bad = 1 }
      END { exit !bad }
    ' "$1"
}

# run_script <step name>: the run block of that step in $WORKFLOW, dedented
run_script() {
  awk -v step="- name: $1" '
    index($0, step) { found = 1; next }
    found && /^ *run: \|/ { indent = index($0, "r") + 2; inrun = 1; next }
    inrun && NF && substr($0, 1, indent - 1) ~ /[^ ]/ { exit }
    inrun { print substr($0, indent) }
  ' "$WORKFLOW"
}

# yaml_ok <file>: parses with yq or PyYAML; status 2 when neither exists
yaml_ok() {
  if command -v yq > /dev/null 2>&1; then
    yq eval '.' "$1" > /dev/null 2>&1
  elif python3 -c 'import yaml' > /dev/null 2>&1; then
    python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$1" > /dev/null 2>&1
  else
    return 2
  fi
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
