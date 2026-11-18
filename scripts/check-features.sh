#!/usr/bin/env bash
# Runs every feature check of the push gate from one committed config
# file, so that no feature has to be wired into the gate by hand:
#
#   0. the working tree must be HEAD, the commit that gets pushed: no file
#      changed from it, none untracked (unless a .gitignore file in the
#      working tree ignores it, committed or not: step 1 fails an
#      untracked one only in or above a locked path), none flagged
#      skip-worktree or assume-unchanged;
#   1. for each "Locked tests: <paths> at <SHA>" line of each feature file
#      (docs/features/*.md): check-locked-tests.sh <SHA> <paths> and
#      check-red-green.sh <SHA> <paths>, with the config's setup, test
#      command and test file globs; and each item's Test cell must name a
#      committed file under those paths that carries the item's tag;
#   2. the project's test run, with the JUnit reports the count file lists
#      deleted first, then check-test-count.sh --since --base;
#   3. check-trace-links.sh over those reports.
#
# Usage: check-features.sh --base <commit>
#
#   --base  the commit the push goes onto, such as origin/main: the count
#           file is compared with its version there
#
# Run it at the top of the repository, or anywhere in it, before a push
# to main or the merge of a pull request. The checks are found next to
# this script (scripts/ in the ai-workflow clone, or the project's
# .ai-workflow/ after hooks/install.sh --gate). Without docs/features/*.md
# there is nothing to check. With feature files, the config file
# feature-checks.conf at the top of the repository is required, and a
# missing or incomplete one fails. Its lines are "<key> = <value>";
# blank lines and lines starting with # are ignored:
#
#   test_command  required: the test command for one test file, with
#                 {path} where the path goes ('npx vitest run {path}')
#   setup         required: the command that installs the dependencies in
#                 a fresh checkout ('npm ci'), or none
#   run           required: the whole test run, which writes the JUnit
#                 reports the count file lists ('npm test')
#   count_file    required: the count file, from the top of the repository;
#                 its reports are deleted before the run, so each must be
#                 a path in the repository that git does not track
#   test_files    optional: the globs that pick the test files in a locked
#                 directory, separated by spaces (check-red-green.sh
#                 --match); its default otherwise
#   scan          optional: test paths, separated by spaces, that
#                 check-trace-links.sh scans for stale or misspelled tags
#                 (OpenFastTrace tags there are not read as item tags)
#   timeout       optional: the limit on each setup, test and run command,
#                 in whole seconds (default 600)
#
# Every feature file with item rows needs at least one line
# "Locked tests: <paths> at <SHA>" at the start of a line: the SHA is the
# test: commit, and the paths, separated by spaces, are from the top of
# the repository. More than one such line is allowed (tests locked in two
# commits); each is checked. Only the template's own placeholder line,
# "Locked tests: <paths> at <SHA of the `test:` commit>", is skipped; any
# other value that is not "<paths> at <SHA>" fails, and so does a line
# that only looks like one (another case, Markdown decoration around
# it). Each item's Test cell starts with its test file (or directory),
# which must be committed, lie under a locked path of the same feature
# file and carry the item's tag at its Rev (F3-2-r1 or f3_2_r1). The count
# file may be missing from the base only when the base has no
# feature-checks.conf either: the change that brings in the feature
# checks.
#
# Exit status: 0 every check passed, 1 a check failed (each check names
# its problems on stderr; a summary follows), 2 bad arguments or a bad
# config file.
set -eu

usage() { echo "Usage: check-features.sh --base <commit>" >&2; exit 2; }
die() { echo "check-features.sh: $*" >&2; exit 2; }
case ${1:-} in
  -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
esac
here=$(cd "$(dirname "$0")" && pwd)

base=
while [ "$#" -gt 0 ]; do
  case $1 in
    --base) [ "$#" -ge 2 ] || usage; base=$2; shift 2 ;;
    *) usage ;;
  esac
done
[ -n "$base" ] || usage
command -v timeout > /dev/null 2>&1 || die "needs timeout (GNU coreutils)"

top=$(git rev-parse --show-toplevel 2> /dev/null) || die "not inside a git work tree"
cd "$top"
git rev-parse --verify --quiet "$base^{commit}" > /dev/null || die "unknown commit: $base"

# The feature files, dot-named ones too, as check-trace-links.sh and
# check-walkthrough list them.
docs=()
if [ -d docs/features ]; then
  while IFS= read -r doc; do docs+=("$doc"); done < <(
    find docs/features -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort
  )
fi
if [ "${#docs[@]}" -eq 0 ]; then
  echo "check-features.sh: no docs/features/*.md: nothing to check"
  exit 0
fi

# --- the config file
config=feature-checks.conf
[ -f "$config" ] || die "$config is missing: with feature files, the feature checks need it (see check-features.sh --help)"
test_command='' setup='' run='' count_file='' test_files='' scan='' limit=600
seen=' '
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  key=${entry%%$'\t'*}
  value=${entry#*$'\t'}
  case $key in
    '!'*) die "$config:${key#!}: not '<key> = <value>': $value" ;;
  esac
  case $seen in *" $key "*) die "$config: $key is set twice" ;; esac
  seen="$seen$key "
  case $key in
    test_command) test_command=$value ;;
    setup) setup=$value ;;
    run) run=$value ;;
    count_file) count_file=$value ;;
    test_files) test_files=$value ;;
    scan) scan=$value ;;
    timeout) limit=$value ;;
    *) die "$config: unknown key '$key'" ;;
  esac
done < <(awk '
  { sub(/\r$/, "") }
  /^[ \t]*(#|$)/ { next }
  /^[ \t]*[a-z_]+[ \t]*=/ {
    key = $0; sub(/^[ \t]*/, "", key); sub(/[ \t]*=.*/, "", key)
    value = $0; sub(/^[^=]*=[ \t]*/, "", value); sub(/[ \t]+$/, "", value)
    printf "%s\t%s\n", key, value
    next
  }
  { printf "!%d\t%s\n", NR, $0 }
' "$config")
for key in test_command setup run count_file; do
  eval "value=\$$key"
  [ -n "$value" ] || die "$config: $key is required (see check-features.sh --help)"
done
case $test_command in *'{path}'*) ;; *) die "$config: test_command must contain {path}: $test_command" ;; esac
[[ $limit =~ ^[1-9][0-9]*$ ]] || die "$config: timeout must be whole seconds, not '$limit'"
[ -f "$count_file" ] || die "$config: no such count file: $count_file"
red_green=(--timeout "$limit")
[ "$setup" = none ] || red_green+=(--setup "$setup")
# Split on blanks, never expanded as globs here.
read -r -a words <<< "$test_files"
for glob in ${words[@]+"${words[@]}"}; do red_green+=(--match "$glob"); done
scans=()
read -r -a words <<< "$scan"
for path in ${words[@]+"${words[@]}"}; do scans+=(--scan "$path"); done

failed=()
# gate <name> <command...>: runs one check; a failure is noted, not fatal
gate() {
  local name=$1
  shift
  echo "== $name"
  if "$@"; then return 0; fi
  failed+=("$name")
}
# problem <where> <message>: a failure found here, not by a check
problem() {
  echo "check-features.sh: $2" >&2
  failed+=("$1")
}

# --- 0. the working tree is HEAD
# The test run, the count and the trace links read the working tree, so
# it must be the commit that gets pushed. Counted as in check-red-green.sh:
# files changed from HEAD, untracked files and files flagged skip-worktree
# or assume-unchanged. Any .gitignore file in the working tree may hide an
# untracked file, an untracked .gitignore included: check-red-green.sh and
# check-locked-tests.sh fail one in or above a locked path (D120), but
# outside the locked paths one that ignores itself hides the files next
# to it, here too. .git/info/exclude and a global excludes file hide
# nothing.
head_is_tree() {
  local changed untracked flagged
  changed=$(set -o pipefail; git diff -z --name-only HEAD | tr -cd '\0' | wc -c | tr -d ' ') ||
    die "git diff failed"
  untracked=$(set -o pipefail; git ls-files -z --others --exclude-per-directory=.gitignore |
    tr -cd '\0' | wc -c | tr -d ' ') || die "git ls-files failed"
  flagged=$(set -o pipefail; git ls-files -v | awk '/^[a-zS] / { n++ } END { print n + 0 }') ||
    die "git ls-files -v failed"
  [ "$changed" -eq 0 ] && [ "$untracked" -eq 0 ] && [ "$flagged" -eq 0 ] && return 0
  echo "check-features.sh: the working tree is not HEAD ($changed changed, $untracked untracked, $flagged flagged skip-worktree or assume-unchanged): the checks would read files that are not pushed; commit them or stash them (git status --short --untracked-files=all lists most of them)" >&2
  return 1
}
gate "the working tree is HEAD" head_is_tree

# --- 1. locked tests, per feature
# SC2016: the template's placeholder holds literal backticks.
# shellcheck disable=SC2016
PLACEHOLDER='<paths> at <SHA of the `test:` commit>'
# normal <path>: the path without a leading ./ or a trailing /
normal() {
  local p=$1
  while [ "${p#./}" != "$p" ]; do p=${p#./}; done
  while [ "${p%/}" != "$p" ]; do p=${p%/}; done
  printf '%s\n' "${p:-.}"
}
# item_test <doc> <line> <ID> <Rev> <Test cell>: the cell's first path
# (up to a blank, comma or semicolon; backticks dropped) is committed,
# lies under one of the paths in $locked, and carries the item's tag
item_test() {
  local where="$1:$2" id=$3 rev=$4 cell=$5 path lock under=0 lower re
  path=${cell//\`/}
  path=${path#"${path%%[![:blank:]]*}"}
  path=${path%%[[:blank:],;]*}
  case $path in
    '' | - | — | – | '<'*)
      echo "check-features.sh: $where: item $id names no test file in its Test cell ('$cell'): name the locked test file that carries its tag" >&2
      return 1 ;;
  esac
  path=$(normal "$path")
  for lock in ${locked[@]+"${locked[@]}"}; do
    case $path in "$lock" | "$lock"/*) under=1 ;; esac
    if [ "$lock" = . ]; then under=1; fi
  done
  if [ "$under" -eq 0 ]; then
    echo "check-features.sh: $where: item $id's test $path is under no locked path of $1 (${locked[*]:-none}): lock it on a Locked tests: line" >&2
    return 1
  fi
  if ! git cat-file -e "HEAD:$path" 2> /dev/null; then
    echo "check-features.sh: $where: item $id's test $path is not in HEAD: commit it" >&2
    return 1
  fi
  # A bad ID or Rev is the trace check's to name.
  [[ $id =~ ^F[1-9][0-9]*-[1-9][0-9]*$ && $rev =~ ^[1-9][0-9]*$ ]] || return 0
  lower=$(printf '%s' "$id" | tr 'F-' 'f_')_r$rev
  re="(^|[^A-Za-z0-9])($id-r$rev|$lower)([^A-Za-z0-9]|\$)"
  if ! git --literal-pathspecs grep -q -E -e "$re" HEAD -- "$path"; then
    echo "check-features.sh: $where: item $id's test $path does not carry its tag $id-r$rev (or $lower) in HEAD" >&2
    return 1
  fi
}

for doc in "${docs[@]}"; do
  parsed=$(awk -f "$here/feature-tables.awk" "$doc") || die "could not read $doc"
  locks=0
  locked=()
  while IFS=$'\t' read -r kind line value; do
    case $kind in
      K)
        problem "$doc:$line" "$doc:$line: '$value' looks like a Locked tests: line, but only a line that starts with exactly 'Locked tests:' is read: write 'Locked tests: <paths> at <SHA>'"
        continue ;;
      L) ;;
      *) continue ;;
    esac
    [ "$value" != "$PLACEHOLDER" ] || continue # the template's own line
    re='^(.+)[[:blank:]]+at[[:blank:]]+([0-9a-f]{7,40})$'
    if ! [[ $value =~ $re ]]; then
      problem "$doc:$line" "$doc:$line: 'Locked tests: $value' is not 'Locked tests: <paths> at <SHA>'"
      continue
    fi
    locks=$((locks + 1))
    sha=${BASH_REMATCH[2]}
    read -r -a paths <<< "${BASH_REMATCH[1]}"
    for path in "${paths[@]}"; do locked+=("$(normal "$path")"); done
    gate "$doc:$line locked tests unchanged" bash "$here/check-locked-tests.sh" "$sha" "${paths[@]}"
    gate "$doc:$line red on the base, green on the head" \
      bash "$here/check-red-green.sh" "${red_green[@]}" "$sha" "$test_command" "${paths[@]}"
  done <<< "$parsed"
  # Items as "<line> US <ID> US <Rev> US <Test>": the unit separator, as
  # blanks collapse and a cell may be empty.
  items=$(printf '%s\n' "$parsed" | awk -F '\t' '$1 == "I" { printf "%s\037%s\037%s\037%s\n", $2, $3, $4, $6 }')
  if [ -z "$items" ]; then
    echo "check-features.sh: note: $doc has no item rows; nothing to lock"
    continue
  fi
  if [ "$locks" -eq 0 ]; then
    problem "$doc" "$doc: it has items, but no filled 'Locked tests: <paths> at <SHA>' line: while the test-writer experiment lasts, every feature file with items needs one"
  fi
  while IFS=$'\037' read -r line id rev test; do
    item_test "$doc" "$line" "$id" "$rev" "$test" || failed+=("$doc:$line")
  done <<< "$items"
done

# --- 2. the test run and the test count
reports=()
while IFS= read -r report; do reports+=("$report"); done < <(
  awk '{ sub(/\r$/, "") } $1 ~ /^[0-9]+$/ && NF == 2 { print $2 }' "$count_file"
)
[ "${#reports[@]}" -gt 0 ] || die "$count_file lists no report"
dir=$(dirname "$count_file")
# Each report is deleted before the run, so each must be a file the run
# writes: inside the repository (through no symbolic link out of it) and
# not tracked by git. All are checked before any is deleted.
real_top=$(pwd -P)
for report in "${reports[@]}"; do
  path=$dir/$report
  case $report in
    /* | [A-Za-z]:*) die "$count_file: the report $report is not a path in the repository" ;;
  esac
  case /$path/ in
    */../*) die "$count_file: the report $path leaves the repository" ;;
  esac
  [ ! -d "$path" ] || die "$count_file: the report $path is a directory"
  if git --literal-pathspecs ls-files --error-unmatch -- "$path" > /dev/null 2>&1; then
    die "$count_file: the report $path is a file git tracks; the gate deletes each report before the test run, so list only reports the run writes"
  fi
  parent=$(dirname -- "$path")
  if [ -d "$parent" ]; then
    real=$(cd -P -- "$parent" && pwd -P) || die "cannot read the directory of the report $path"
    case $real/ in
      "$real_top"/*) ;;
      *) die "$count_file: the report $path is outside the repository ($real)" ;;
    esac
  fi
done
for report in "${reports[@]}"; do rm -f -- "$dir/$report"; done
stamp=$(mktemp) || die "could not make a stamp file"
trap 'rm -f "$stamp"' EXIT
echo "== the test run: $run"
status=0
timeout -k 10 "$limit" bash -c "$run" < /dev/null || status=$?
if [ "$status" -ne 0 ]; then
  echo "check-features.sh: the test run exited with $status: $run" >&2
  failed+=("the test run")
fi
count=(--since "$stamp" --base "$base")
git cat-file -e "$base:$config" 2> /dev/null || count+=(--allow-new-count-file)
gate "test count" bash "$here/check-test-count.sh" "${count[@]}" "$count_file"

# --- 3. trace links
traced=()
for report in "${reports[@]}"; do traced+=("$dir/$report"); done
gate "trace links" bash "$here/check-trace-links.sh" ${scans[@]+"${scans[@]}"} docs/features "${traced[@]}"

if [ "${#failed[@]}" -gt 0 ]; then
  echo "check-features.sh: failed:" >&2
  printf '  %s\n' "${failed[@]}" >&2
  exit 1
fi
echo "check-features.sh: every feature check passed"
