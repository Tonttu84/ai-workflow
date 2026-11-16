#!/usr/bin/env bash
# Tests for scripts/check-features.sh: every feature file's locked tests
# are checked (unchanged, red on the base, green on the head) without any
# wiring by hand, then the test run, the test count and the trace links,
# all from one committed config file.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp
clear_git_env # the tests run git; an outer hook's GIT_* must not steer it

FEATURES="$ROOT/scripts/check-features.sh"
scratch="$TMP/scratch"
mkdir -p "$scratch"

# new_repo <dir>
new_repo() {
  git init -q -b main "$1"
  git -C "$1" config user.name test
  git -C "$1" config user.email test@example.com
  git -C "$1" config core.autocrlf false
}

repo="$TMP/project"
new_repo "$repo"
mkdir -p "$repo/e2e" "$repo/src"
# The fake per-file runner: runs every *.test.sh under the paths given.
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
# The fake whole run: runs every test and writes a JUnit report whose
# testcase names come from each test's "# name:" line.
cat > "$repo/run-all.sh" << 'EOF'
mkdir -p reports
bad=0
{
  printf '<testsuites>\n<testsuite name="all">\n'
  for t in $(find . -name '*.test.sh' -not -path './.git/*' | sort); do
    name=$(sed -n 's/^# name: //p' "$t")
    if bash "$t" < /dev/null > /dev/null 2>&1; then
      printf '<testcase name="%s"/>\n' "$name"
    else
      printf '<testcase name="%s"><failure message="x"/></testcase>\n' "$name"
      bad=1
    fi
  done
  printf '</testsuite>\n</testsuites>\n'
} > reports/all.xml
exit "$bad"
EOF
printf 'reports/\n' > "$repo/.gitignore"
printf 'echo ""\n' > "$repo/src/greet.sh"
git -C "$repo" add -A
git -C "$repo" commit -q -m "feat: start"
before=$(git -C "$repo" rev-parse HEAD)

# greet_test <file> <tag> <expected greeting>
# shellcheck disable=SC2016
greet_test() {
  printf '# name: %s greets\nhere=$(dirname "$0")\n[ "$(bash "$here/../src/greet.sh")" = %s ]\n' "$2" "$3" > "$1"
}
greet_test "$repo/e2e/one.test.sh" F1-1-r1 hello
git -C "$repo" add -A
git -C "$repo" commit -q -m "test: lock the greeting test"
locked=$(git -C "$repo" rev-parse HEAD)

mkdir -p "$repo/docs/features"
# feature_file <file> <id> <test cell> <locked tests line or ->
feature_file() {
  {
    printf '# Feature: greeting\n\n'
    printf '| ID | Rev | Item | Entry point | Expected outcome | Level | Test |\n'
    printf '| --- | --- | --- | --- | --- | --- | --- |\n'
    printf '| %s | 1 | greet | greet.sh | prints hello | — | %s |\n\n' "$2" "$3"
    [ "$4" = - ] || printf 'Locked tests: %s\n\n' "$4"
    printf 'Walkthrough:\n'
  } > "$repo/docs/features/$1"
}
feature_file greet.md F1-1 'e2e/one.test.sh, F1-1-r1' "e2e at $locked"
CONFIG='# The feature checks (scripts/check-features.sh).
test_command = bash run-tests.sh {path}
setup = none
run = bash run-all.sh
count_file = .test-count
scan = e2e
timeout = 60
'
printf '%s' "$CONFIG" > "$repo/feature-checks.conf"
printf '1 reports/all.xml\n' > "$repo/.test-count"
printf 'echo hello\n' > "$repo/src/greet.sh"
git -C "$repo" add -A
git -C "$repo" commit -q -m "feat: greet"
head=$(git -C "$repo" rev-parse HEAD)

# features [args...]: runs the script in the repo; stdout in $TMP/out,
# stderr in $TMP/err
features() { (cd "$repo" && TMPDIR="$scratch" bash "$FEATURES" "$@") > "$TMP/out" 2> "$TMP/err"; }
status_is() {
  local want=$1
  shift
  features "$@"
  [ "$?" -eq "$want" ]
}
says() { grep -qF -- "$1" "$TMP/err"; }
prints() { grep -qF -- "$1" "$TMP/out"; }
reset_repo() {
  git -C "$repo" reset -q --hard "$head" && git -C "$repo" clean -qfdx
  rm -rf "${scratch:?}"/*
}
commit_all() { git -C "$repo" add -A && git -C "$repo" commit -q -m "$1"; }
set_config() { printf '%s' "$1" > "$repo/feature-checks.conf"; }

# --- arguments
check "--help prints the comment block and no code" help_ok "$FEATURES"
check "no --base: usage error" status_is 2
check "it prints the usage" says 'Usage'
check "an unknown base: error" status_is 2 --base no-such-ref
check "it names the base" says no-such-ref
check "an unknown option: usage error" status_is 2 --bogus

# --- every check passes
check "a feature whose checks all hold passes" status_is 0 --base "$head"
check "it ran the locked-tests check" prints 'docs/features/greet.md:7 locked tests unchanged'
check "it ran red-green" prints 'e2e/one.test.sh: base failed, head passed'
check "it ran the test count" prints 'reports/all.xml'
check "it ran the trace links" prints 'F1-1'
check "it says every check passed" prints 'every feature check passed'
from_e2e() { (cd "$repo/e2e" && TMPDIR="$scratch" bash "$FEATURES" --base "$head") > "$TMP/out" 2> "$TMP/err"; }
from_e2e
check "it runs from a subdirectory too" test "$?" -eq 0
check "the working tree is left clean" test -z "$(git -C "$repo" status --porcelain)"
reset_repo

# --- no feature files, or no config
plain="$TMP/plain"
new_repo "$plain"
git -C "$plain" commit -q --allow-empty -m "chore: start"
plain_run() { (cd "$plain" && bash "$FEATURES" --base HEAD) > "$TMP/out" 2> "$TMP/err"; }
plain_run
check "no feature files: nothing to check" test "$?" -eq 0
check "it says so" prints 'nothing to check'
mkdir -p "$plain/docs/features"
cp "$repo/docs/features/greet.md" "$plain/docs/features/"
plain_run
check "feature files without the config file: error" test "$?" -eq 2
check "it names the config file" says 'feature-checks.conf'

# --- a config file that is missing a part, or has a wrong one
for key in test_command setup run count_file; do
  set_config "$(printf '%s' "$CONFIG" | grep -v "^$key ")"
  commit_all "chore: drop $key"
  check "a config without $key: error" status_is 2 --base "$head"
  check "it names $key" says "$key"
  reset_repo
done
set_config "$CONFIG
colour = blue
"
commit_all "chore: an unknown key"
check "an unknown key: error" status_is 2 --base "$head"
check "it names the key" says colour
reset_repo
set_config "$CONFIG
this line has no equals sign
"
commit_all "chore: a bad line"
check "a line that is not key = value: error" status_is 2 --base "$head"
reset_repo
set_config "$CONFIG
setup = npm ci
"
commit_all "chore: setup twice"
check "a key set twice: error" status_is 2 --base "$head"
reset_repo
set_config "$(printf '%s' "$CONFIG" | sed 's/{path}//')"
commit_all "chore: no {path}"
check "a test command without {path}: error" status_is 2 --base "$head"
reset_repo

# Globs in the config are passed on as globs, not expanded against the
# files at the top of the repository (run-all.sh, run-tests.sh).
set_config "$CONFIG
test_files = *.sh
"
commit_all "chore: test files by glob"
check "a test_files glob that matches files at the top still picks the test files" status_is 0 --base "$head"
check "the test file ran" prints 'e2e/one.test.sh: base failed, head passed'
reset_repo

# --- a feature added later is checked without any wiring
mkdir -p "$repo/e2e2"
printf '# name: F2-1-r1 is vacuous\ntrue\n' > "$repo/e2e2/vacuous.test.sh"
commit_all "test: lock the second feature's test"
second=$(git -C "$repo" rev-parse HEAD)
feature_file second.md F2-1 'e2e2/vacuous.test.sh' "e2e2 at $second"
commit_all "feat: the second feature"
check "a second feature with a vacuous locked test fails" status_is 1 --base "$head"
check "red-green names the vacuous test" says 'e2e2/vacuous.test.sh passes on the base'
check "the summary names the feature" says 'docs/features/second.md'
reset_repo

# --- the Locked tests line
feature_file greet.md F1-1 'e2e/one.test.sh, F1-1-r1' -
commit_all "docs: drop the locked tests line"
check "an item with a Test and no Locked tests line fails" status_is 1 --base "$head"
check "it says the line is missing" says 'no filled'
feature_file greet.md F1-1 'e2e/one.test.sh, F1-1-r1' '<paths> at <SHA of the `test:` commit>'
commit_all "docs: the placeholder"
check "the template's placeholder counts as missing" status_is 1 --base "$head"
check "it says the line is missing, not malformed" says 'no filled'
feature_file greet.md F1-1 '—' '<paths> at <SHA of the `test:` commit>'
commit_all "docs: no tests yet"
features --base "$head"
check "the placeholder with no Test filled is only a note" prints 'has no locked tests yet'
refute "and is not called malformed" says "is not 'Locked tests"
feature_file greet.md F1-1 'e2e/one.test.sh, F1-1-r1' 'e2e, at some point'
commit_all "docs: a malformed line"
check "a malformed Locked tests line fails" status_is 1 --base "$head"
check "it quotes the line" says 'e2e, at some point'
reset_repo

# --- each check can fail the gate
printf 'true\n' >> "$repo/e2e/one.test.sh"
commit_all "fix: weaken the locked test"
check "a weakened locked test fails" status_is 1 --base "$head"
check "the locked-tests check names it" says 'changed: e2e/one.test.sh'
reset_repo

set_config "$(printf '%s' "$CONFIG" | sed 's/^setup = none$/setup = exit 3/')"
commit_all "chore: a broken setup"
check "a setup that fails fails the gate" status_is 1 --base "$head"
check "red-green says the setup failed" says 'setup'
reset_repo

set_config "$(printf '%s' "$CONFIG" | sed 's/^run = .*/run = true/')"
commit_all "chore: a run that writes no report"
mkdir -p "$repo/reports"
printf '<testsuites><testsuite><testcase name="F1-1-r1 greets"/></testsuite></testsuites>\n' > "$repo/reports/all.xml"
check "a report left from an earlier run is deleted, so a run that writes none fails" \
  status_is 1 --base "$head"
check "it says the report is missing" says 'no such report'
reset_repo

sed 's/^exit "\$bad"$/exit 1/' "$repo/run-all.sh" > "$TMP/r" && cp "$TMP/r" "$repo/run-all.sh"
commit_all "chore: a failing run"
check "a test run that fails fails the gate" status_is 1 --base "$head"
check "it says the run failed" says 'the test run exited with 1'
reset_repo

printf '0 reports/all.xml\n' > "$repo/.test-count"
commit_all "test: lower the count"
check "a count lowered below the base's fails" status_is 1 --base "$head"
check "the count check says so" says 'the base lists 1'
reset_repo

# A Rev bump leaves the locked test at the old revision: only the trace
# check can see it.
sed 's/^| F1-1 | 1 |/| F1-1 | 2 |/' "$repo/docs/features/greet.md" > "$TMP/f" &&
  cp "$TMP/f" "$repo/docs/features/greet.md"
commit_all "docs: bump F1-1"
check "an item whose test is at an old revision fails" status_is 1 --base "$head"
check "the trace check says the link is stale" says 'stale'
check "the summary names the trace check" says 'trace links'
refute "the locked-tests check is not blamed" says 'locked tests unchanged'
reset_repo

# --- the count file and the base
check "a base without the config or count file passes: the gate's first change" \
  status_is 0 --base "$before"
check "it notes the first count file" says 'first count file'
git -C "$repo" mv .test-count ci-count
set_config "$(printf '%s' "$CONFIG" | sed 's/^count_file = .*/count_file = ci-count/')"
commit_all "chore: move the count file"
check "a count file moved away from the base's fails" status_is 1 --base "$head"
check "it says the base has no count file there" says 'no count file'
reset_repo

check "nothing is left behind" test -z "$(ls -A "$scratch")"
finish
