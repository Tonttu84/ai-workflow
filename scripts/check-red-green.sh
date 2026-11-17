#!/usr/bin/env bash
# Checks that each locked test needs the feature: it fails on the code
# before the feature and passes on the code with it.
#
# Usage: check-red-green.sh [--timeout <seconds>] [--setup <command>]
#                           [--match <glob>]... <base> <command> <path>...
#
#   base       the code before the feature: the commit the test writer
#              started from, or the test: commit itself
#   command    the project's test command for one test file, with {path}
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
#   --match    which files in a locked directory are test files, as a
#              shell glob on the file name; repeat it for more than one.
#              The default: *.test.* *.spec.* test_*.py *_test.py
#
# The base is checked out in a temporary git worktree, and the locked
# tests are copied into it from the working tree: every file git tracks
# or would track under each path, helpers included. Each test file then
# runs on its own, a file given by name whatever its name, and in a
# directory each file --match picks: one test that passes on the base is
# not hidden by others that fail. On the base it must fail, and in the
# working tree (the head) it must pass. The working tree must be HEAD,
# the commit that gets pushed: a file changed, untracked (unless a
# .gitignore file ignores it) or flagged skip-worktree or
# assume-unchanged fails the check, since the head side would run code
# that is not pushed; so does an untracked .gitignore in or above a
# locked path, ignored or not, since one that ignores itself hides what
# is next to it. Outside the locked paths such a .gitignore still hides
# what is next to it. The temporary worktree is always removed.
#
# Limits: the tests inside one file still run together, so a vacuous
# test next to a failing one in the same file is not found. The script
# cannot tell why a test failed on the base: a test that fails only
# because a dependency is missing counts as failing. Give --setup the
# install command, and check the reason in the test writer's report.
#
# Exit status: 0 every test file failed on the base and passed on the
# head, 1 a file passed on the base, or failed on the head, or a run timed
# out, or the working tree is not HEAD (each is named on stderr), 2 bad
# arguments or a setup failure (no worktree, a failed --setup, a command
# that is not found, a locked path with no file git tracks, a directory
# with no test file).
set -eu

usage() {
  echo "Usage: check-red-green.sh [--timeout <seconds>] [--setup <command>] [--match <glob>]... <base> <command> <path>..." >&2
  exit 2
}
die() { echo "check-red-green.sh: $*" >&2; exit 2; }
case ${1:-} in
  -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
esac

limit=600
setup=
globs=()
while [ "$#" -gt 0 ]; do
  case $1 in
    --timeout) [ "$#" -ge 2 ] || usage; limit=$2; shift 2 ;;
    --setup) [ "$#" -ge 2 ] || usage; setup=$2; shift 2 ;;
    --match) [ "$#" -ge 2 ] && [ -n "$2" ] || usage; globs+=("$2"); shift 2 ;;
    --) shift; break ;;
    -*) die "unknown option: $1" ;;
    *) break ;;
  esac
done
[ "$#" -ge 3 ] || usage
[[ $limit =~ ^[1-9][0-9]*$ ]] || die "the timeout must be whole seconds, not '$limit'"
[ "${#globs[@]}" -gt 0 ] || globs=('*.test.*' '*.spec.*' 'test_*.py' '*_test.py')
command -v timeout > /dev/null 2>&1 || die "needs timeout (GNU coreutils)"

git() { command git --literal-pathspecs -c core.quotePath=false "$@"; }

# untracked_ignores <path>...: the untracked .gitignore files, ignored or
# not, in or above the paths, from the top of the repository, one per
# line. One that ignores itself hides the files next to it from git, and
# no other clone has it. The name is matched in any case: git on a
# case-insensitive file system (Windows, macOS) reads .GITIGNORE too.
untracked_ignores() {
  local path dir rel out icase=':(icase,literal)' specs=()
  for path in "$@"; do
    if [ -d "$path" ]; then dir=$path; else dir=$(dirname -- "$path"); fi
    while [ ! -d "$dir" ]; do dir=$(dirname -- "$dir"); done
    rel=$(cd -- "$dir" && command git rev-parse --show-prefix) || return 1
    if [ -d "$path" ]; then specs+=("$icase${rel:-.}"); fi
    while :; do
      specs+=("$icase${rel}.gitignore")
      [ -n "$rel" ] || break
      rel=${rel%/}
      case $rel in */*) rel=${rel%/*}/ ;; *) rel= ;; esac
    done
  done
  # Pathspec magic, so not the git() above (--literal-pathspecs), and
  # with the environment's global pathspec settings off.
  out=$(
    GIT_LITERAL_PATHSPECS=0 GIT_GLOB_PATHSPECS=0 GIT_NOGLOB_PATHSPECS=0 GIT_ICASE_PATHSPECS=0 \
      command git -C "$(git rev-parse --show-toplevel)" ls-files -z --others -- "${specs[@]}" | tr '\0' '\n'
    exit "${PIPESTATUS[0]}"
  ) || return 1
  printf '%s\n' "$out" | awk -F / 'tolower($NF) == ".gitignore"'
}
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

# The head side runs in the working tree, so it must be HEAD, the commit
# that gets pushed. Counted: files in the working tree changed from HEAD,
# untracked files (any .gitignore file in the working tree may hide one,
# an untracked one outside the locked paths included: untracked_ignores
# fails one only in or above a locked path; .git/info/exclude and a
# global excludes file hide none, since they reach no other clone), and
# files flagged skip-worktree or assume-unchanged, which hides a change
# from git.
top=$(git rev-parse --show-toplevel)
git -C "$top" diff -z --name-only HEAD > "$tmp/changed" || die "git diff failed"
git -C "$top" ls-files -z --others --exclude-per-directory=.gitignore > "$tmp/untracked" ||
  die "git ls-files failed"
git -C "$top" ls-files -v > "$tmp/flags" || die "git ls-files -v failed"
changed=$(tr -cd '\0' < "$tmp/changed" | wc -c | tr -d ' ')
untracked=$(tr -cd '\0' < "$tmp/untracked" | wc -c | tr -d ' ')
flagged=$(awk '/^[a-zS] / { n++ } END { print n + 0 }' "$tmp/flags")
untracked_ignores "$@" > "$tmp/ignores" || die "git ls-files failed on the .gitignore files"
ignores=$(awk 'NF { n++ } END { print n + 0 }' "$tmp/ignores")

timeout -k 10 "$limit" git worktree add --quiet --detach "$wt" "$base" > "$tmp/add.log" 2>&1 ||
  die "could not check out $base in a temporary worktree: $(tail -n 3 "$tmp/add.log")"

# test_file <file>: is the file a test file by its name (--match)?
test_file() {
  local name=${1##*/} glob
  for glob in "${globs[@]}"; do
    # The glob is a pattern here, on purpose.
    # shellcheck disable=SC2254
    case $name in $glob) return 0 ;; esac
  done
  return 1
}

# Copy the locked files to the base, and list the test files to run, one
# per line in $tmp/runs (paths cannot hold a newline here).
: > "$tmp/runs"
for path in "$@"; do
  copied=0 tests=0
  while IFS= read -r -d '' file; do
    [ -f "$file" ] || continue # deleted in the working tree
    case $file in *$'\n'*) die "a path with a newline cannot be run: $file" ;; esac
    mkdir -p "$(dirname "$wt/$prefix$file")"
    cp "$file" "$wt/$prefix$file"
    copied=$((copied + 1))
    if [ -d "$path" ] && test_file "$file"; then
      printf '%s\n' "$file" >> "$tmp/runs"
      tests=$((tests + 1))
    fi
  done < <(git ls-files -z --cached --others --exclude-standard -- "$path")
  [ "$copied" -gt 0 ] || die "no files git tracks or would track under $path"
  if [ ! -d "$path" ]; then
    printf '%s\n' "$path" >> "$tmp/runs"
  elif [ "$tests" -eq 0 ]; then
    die "no test file in $path matches ${globs[*]}: name the files, or give --match"
  fi
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

# timeout exits 124 when the limit is hit, and 137 when the command
# ignored SIGTERM and was killed with SIGKILL 10 seconds later.
if [ -n "$setup" ]; then
  status=0
  run "$wt/$prefix" "$tmp/setup.log" "$setup" || status=$?
  if [ "$status" -ne 0 ]; then
    why="exited with $status"
    case $status in 124 | 137) why="timed out after ${limit}s" ;; esac
    die "the setup command $why in the base checkout: $setup
$(tail_of "$tmp/setup.log")"
  fi
fi

short=$(git rev-parse --short "$base")
problems=0
if [ "$changed" -ne 0 ] || [ "$untracked" -ne 0 ] || [ "$flagged" -ne 0 ] || [ "$ignores" -ne 0 ]; then
  echo "check-red-green.sh: the working tree is not HEAD ($changed changed, $untracked untracked, $flagged flagged skip-worktree or assume-unchanged, $ignores untracked .gitignore in or above a locked path): the head side would run code that is not pushed; commit it or stash it (git status --short --untracked-files=all lists most of it)" >&2
  if [ "$ignores" -ne 0 ]; then sed 's/^/  untracked .gitignore: /' "$tmp/ignores" >&2; fi
  problems=$((problems + 1))
fi
# check <side> <dir> <path>: runs one test file on one side and judges it
check() {
  local side=$1 dir=$2 path=$3 status=0 log="$tmp/run.log"
  run "$dir" "$log" "$(expand "$path")" || status=$?
  case $side:$status in
    *:126 | *:127)
      die "$path: the test command exited with $status on the $side (not found or not runnable): $(expand "$path")
$(tail_of "$log")" ;;
    *:124 | *:137)
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
while IFS= read -r path; do
  red=failed green=passed
  check base "$wt/$prefix" "$path" || red=PROBLEM
  check head "." "$path" || green=PROBLEM
  echo "  $path: base $red, head $green"
done < "$tmp/runs"
[ "$problems" -eq 0 ]
