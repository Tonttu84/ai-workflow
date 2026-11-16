#!/usr/bin/env bash
# Checks that each locked test needs the feature: it fails on the code
# before the feature and passes on the code with it.
#
# Usage: check-red-green.sh [--timeout <seconds>] [--setup <command>]
#                           <base> <command> <path>...
#
#   base       the code before the feature: the commit the test writer
#              started from, or the test: commit itself
#   command    the project's test command for one test path, with {path}
#              where the path goes, such as 'npx vitest run {path}' or
#              'uv run pytest {path}'; it runs in bash, in the directory
#              this script runs in
#   path       a locked test file or directory, relative to that directory
#   --timeout  the limit on each run of the setup or test command, in
#              whole seconds (default 600); a run that hits it fails the
#              check, since a hang is neither a pass nor a fail
#   --setup    a command run once in the base checkout before its tests,
#              such as 'npm ci' or 'uv sync': a fresh checkout has no
#              installed dependencies
#
# The base is checked out in a temporary git worktree, and the locked
# tests are copied into it from the working tree (the files git tracks or
# would track under each path). Each path then runs on its own, so one
# test that passes on the base is not hidden by others that fail: on the
# base it must fail, and in the working tree (the head, uncommitted
# changes included) it must pass. The temporary worktree is always
# removed.
#
# The script cannot tell why a test failed on the base: a test that fails
# only because a dependency is missing counts as failing. Give --setup the
# install command, and check the reason in the test writer's report.
#
# Exit status: 0 every path failed on the base and passed on the head,
# 1 a path passed on the base, or failed on the head, or a run timed out
# (each is named on stderr), 2 bad arguments or a setup failure (no
# worktree, a failed --setup, a command that is not found).
set -eu

usage() {
  echo "Usage: check-red-green.sh [--timeout <seconds>] [--setup <command>] <base> <command> <path>..." >&2
  exit 2
}
die() { echo "check-red-green.sh: $*" >&2; exit 2; }
case ${1:-} in
  -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
esac

limit=600
setup=
while [ "$#" -gt 0 ]; do
  case $1 in
    --timeout) [ "$#" -ge 2 ] || usage; limit=$2; shift 2 ;;
    --setup) [ "$#" -ge 2 ] || usage; setup=$2; shift 2 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
[ "$#" -ge 3 ] || usage
[[ $limit =~ ^[1-9][0-9]*$ ]] || die "the timeout must be whole seconds, not '$limit'"
command -v timeout > /dev/null 2>&1 || die "needs timeout (GNU coreutils)"

git() { command git --literal-pathspecs -c core.quotePath=false "$@"; }
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || die "not inside a git work tree"
base=$(git rev-parse --verify --quiet "$1^{commit}") || die "unknown commit: $1"
cmd=$2
shift 2
case $cmd in *'{path}'*) ;; *) die "the command must contain {path}: $cmd" ;; esac
for path in "$@"; do
  [ -n "$path" ] || die "empty path"
  [ -e "$path" ] || die "no such path: $path"
done
prefix=$(git rev-parse --show-prefix) # where this directory is in the repo

tmp=$(mktemp -d) || die "could not make a temporary directory"
wt=$tmp/base
trap 'command git worktree remove --force "$wt" > /dev/null 2>&1; rm -rf "$tmp"; command git worktree prune > /dev/null 2>&1' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

timeout -k 10 "$limit" git worktree add --quiet --detach "$wt" "$base" > "$tmp/add.log" 2>&1 ||
  die "could not check out $base in a temporary worktree: $(tail -n 3 "$tmp/add.log")"

for path in "$@"; do
  copied=0
  while IFS= read -r -d '' file; do
    [ -f "$file" ] || continue # deleted in the working tree
    mkdir -p "$(dirname "$wt/$prefix$file")"
    cp "$file" "$wt/$prefix$file"
    copied=$((copied + 1))
  done < <(git ls-files -z --cached --others --exclude-standard -- "$path")
  [ "$copied" -gt 0 ] || die "no files git tracks or would track under $path"
done

# run <dir> <log> <command>: runs the command in the directory with the
# time limit and no input; returns its exit status
run() { (cd "$1" && timeout -k 10 "$limit" bash -c "$3") > "$2" 2>&1 < /dev/null; }

# expand <path>: the command with every {path} replaced by the quoted path
expand() {
  local rest=$cmd out='' quoted
  quoted=$(printf '%q' "$1")
  while :; do
    case $rest in
      *'{path}'*) out=$out${rest%%'{path}'*}$quoted; rest=${rest#*'{path}'} ;;
      *) out=$out$rest; break ;;
    esac
  done
  printf '%s' "$out"
}

# tail_of <log>: the end of a run's output, indented, for a report
tail_of() { tail -n 20 "$1" | sed 's/^/    | /'; }

if [ -n "$setup" ]; then
  status=0
  run "$wt/$prefix" "$tmp/setup.log" "$setup" || status=$?
  if [ "$status" -ne 0 ]; then
    why="exited with $status"
    [ "$status" -ne 124 ] || why="timed out after ${limit}s"
    die "the setup command $why in the base checkout: $setup
$(tail_of "$tmp/setup.log")"
  fi
fi

short=$(git rev-parse --short "$base")
problems=0
# check <side> <dir> <path>: runs one path on one side and judges it
check() {
  local side=$1 dir=$2 path=$3 status=0 log="$tmp/run.log"
  run "$dir" "$log" "$(expand "$path")" || status=$?
  case $side:$status in
    *:126 | *:127)
      die "$path: the test command exited with $status on the $side (not found or not runnable): $(expand "$path")
$(tail_of "$log")" ;;
    *:124)
      echo "check-red-green.sh: $path timed out on the $side after ${limit}s: neither a pass nor a fail" >&2 ;;
    base:0)
      echo "check-red-green.sh: $path passes on the base $short: it does not need the feature" >&2 ;;
    head:0 | base:*)
      return 0 ;;
    head:*)
      echo "check-red-green.sh: $path fails on the head (exit $status):" >&2
      tail_of "$log" >&2 ;;
  esac
  problems=$((problems + 1))
  return 1
}

echo "Base $short with the locked tests copied in; head is the working tree."
for path in "$@"; do
  red=failed green=passed
  check base "$wt/$prefix" "$path" || red=PROBLEM
  check head "." "$path" || green=PROBLEM
  echo "  $path: base $red, head $green"
done
[ "$problems" -eq 0 ]
