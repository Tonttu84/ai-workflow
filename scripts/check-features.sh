#!/usr/bin/env bash
# Runs every feature check of the push gate from one committed config
# file, so that no feature has to be wired into the gate by hand:
#
#   1. for each "Locked tests: <paths> at <SHA>" line of each feature file
#      (docs/features/*.md): check-locked-tests.sh <SHA> <paths> and
#      check-red-green.sh <SHA> <paths>, with the config's setup, test
#      command and test file globs;
#   2. the project's test run, with the JUnit reports the count file lists
#      deleted first, then check-test-count.sh --since --base;
#   3. check-trace-links.sh over those reports.
#
# Usage: check-features.sh --base <commit>
#
#   --base  the commit the push goes onto, such as origin/main: the count
#           file is compared with its version there
#
# Run it at the top of the repository, or anywhere in it. The checks are
# found next to this script (scripts/ in the ai-workflow clone, or the
# project's .ai-workflow/ after hooks/install.sh --gate). Without
# docs/features/*.md there is nothing to check. With feature files, the
# config file feature-checks.conf at the top of the repository is
# required, and a missing or incomplete one fails. Its lines are
# "<key> = <value>"; blank lines and lines starting with # are ignored:
#
#   test_command  required: the test command for one test file, with
#                 {path} where the path goes ('npx vitest run {path}')
#   setup         required: the command that installs the dependencies in
#                 a fresh checkout ('npm ci'), or none
#   run           required: the whole test run, which writes the JUnit
#                 reports the count file lists ('npm test')
#   count_file    required: the count file, from the top of the repository
#   test_files    optional: the globs that pick the test files in a locked
#                 directory, separated by spaces (check-red-green.sh
#                 --match); its default otherwise
#   scan          optional: test paths, separated by spaces, that
#                 check-trace-links.sh scans for stale or misspelled tags
#   timeout       optional: the limit on each setup, test and run command,
#                 in whole seconds (default 600)
#
# A feature file needs a filled "Locked tests: <paths> at <SHA>" line
# once any of its items has a Test filled in; the SHA is the test:
# commit, and the paths, separated by spaces, are from the top of the
# repository. A line still holding the template's placeholder counts as
# missing. More than one such line is allowed (tests locked in two
# commits); each is checked. The count file may be missing from the base
# only when the base has no feature-checks.conf either: the change that
# brings in the feature checks.
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

docs=()
for doc in docs/features/*.md; do
  if [ -f "$doc" ]; then docs+=("$doc"); fi
done
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

# --- 1. locked tests, per feature
for doc in "${docs[@]}"; do
  parsed=$(awk -f "$here/feature-tables.awk" "$doc") || die "could not read $doc"
  filled=$(printf '%s\n' "$parsed" | awk -F '\t' '$1 == "I" && $6 != "" && $6 !~ /^(-|—|–)$/ && $6 !~ /^</ { n++ } END { print n + 0 }')
  locks=0
  while IFS=$'\t' read -r kind line value; do
    [ "$kind" = L ] || continue
    case $value in
      '' | *'<'*)
        continue ;; # empty, or the template's placeholder
    esac
    re='^(.+)[[:blank:]]+at[[:blank:]]+([0-9a-f]{7,40})$'
    if ! [[ $value =~ $re ]]; then
      echo "check-features.sh: $doc:$line: 'Locked tests: $value' is not 'Locked tests: <paths> at <SHA>'" >&2
      failed+=("$doc:$line")
      continue
    fi
    locks=$((locks + 1))
    sha=${BASH_REMATCH[2]}
    read -r -a paths <<< "${BASH_REMATCH[1]}"
    gate "$doc:$line locked tests unchanged" bash "$here/check-locked-tests.sh" "$sha" "${paths[@]}"
    gate "$doc:$line red on the base, green on the head" \
      bash "$here/check-red-green.sh" "${red_green[@]}" "$sha" "$test_command" "${paths[@]}"
  done <<< "$parsed"
  if [ "$locks" -eq 0 ] && [ "$filled" -gt 0 ]; then
    echo "check-features.sh: $doc: $filled item(s) have a Test, but there is no filled 'Locked tests: <paths> at <SHA>' line" >&2
    failed+=("$doc")
  elif [ "$locks" -eq 0 ]; then
    echo "check-features.sh: note: $doc has no locked tests yet"
  fi
done

# --- 2. the test run and the test count
reports=()
while IFS= read -r report; do reports+=("$report"); done < <(
  awk '{ sub(/\r$/, "") } $1 ~ /^[0-9]+$/ && NF == 2 { print $2 }' "$count_file"
)
[ "${#reports[@]}" -gt 0 ] || die "$count_file lists no report"
dir=$(dirname "$count_file")
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
