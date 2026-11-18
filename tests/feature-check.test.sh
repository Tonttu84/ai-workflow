#!/usr/bin/env bash
# Tests for templates/feature-check.yml, the CI job of a public showcase
# project with feature files (D129, D137): the workflow is hardened, runs
# on pull requests only, on the pull request's head with full history and
# the pull-request refs, and its run scripts check a pull request in a
# fresh clone of a bare remote, as the job would on GitHub. What the
# checkout action itself does can only be proved there.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp
clear_git_env # the tests run git; an outer hook's GIT_* must not steer it
GIT_CONFIG_GLOBAL="$TMP/global.gitconfig"
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
printf '[user]\n\tname = test\n\temail = test@example.com\n[core]\n\tautocrlf = false\n' \
  > "$GIT_CONFIG_GLOBAL"
mkdir -p "$TMP/runner" "$TMP/tmpdir"

WORKFLOW="$ROOT/templates/feature-check.yml" # run_script (lib.sh) reads it
FETCH='Fetch the pull-request refs'
TOOLCHAIN='Toolchain and dependencies (fill in)'
CHECKS='The feature checks and the walkthrough check'
check "feature-check.yml exists" test -f "$WORKFLOW"

# --- hardened, as commit-check.yml is
# differs <mutant>: the mutant is not the workflow
differs() { test -n "$(diff "$WORKFLOW" "$1" 2> /dev/null)"; }
check "feature-check.yml is hardened" hardened "$WORKFLOW"
sed 's/@3d3c42e5aac5ba805825da76410c181273ba90b1/@v7/' "$WORKFLOW" > "$TMP/unpinned.yml"
check "the unpinned mutant differs" differs "$TMP/unpinned.yml"
refute "an unpinned action is noticed" hardened "$TMP/unpinned.yml"
# SC2016: sed inserts a literal expression.
# shellcheck disable=SC2016
sed 's/ != "\$PR_HEAD" \]; then$/ != "${{ github.event.pull_request.head.sha }}" ]; then/' \
  "$WORKFLOW" > "$TMP/inject.yml"
check "the injection mutant differs" differs "$TMP/inject.yml"
refute "an expression inside a run script is noticed" hardened "$TMP/inject.yml"
grep -v 'timeout-minutes' "$WORKFLOW" > "$TMP/no-timeout.yml"
check "the no-timeout mutant differs" differs "$TMP/no-timeout.yml"
refute "a job without a timeout is noticed" hardened "$TMP/no-timeout.yml"
check "the runner is pinned" \
  test "$(count 'runs-on: ubuntu-24.04$' "$WORKFLOW")" -eq "$(count 'runs-on: ' "$WORKFLOW")"
yaml_ok "$WORKFLOW"
case $? in
  0) pass ;;
  2) printf 'feature-check.test.sh: SKIP: no YAML parser (yq or PyYAML) to parse feature-check.yml\n' ;;
  *) fail "feature-check.yml parses as YAML" ;;
esac

# --- pull requests into main only, never the _target variant, which
# runs with write access
# triggers <workflow>: the events under on:, one per line
triggers() {
  awk '/^on:/ { on = 1; next } on && /^[^ #]/ { exit } on && /^  [A-Za-z_]+:/ { t = $1; sub(/:$/, "", t); print t }' "$1"
}
check "it runs on pull requests only" test "$(triggers "$WORKFLOW")" = pull_request
refute "it never names pull_request_target" grep -q 'pull_request_target' "$WORKFLOW"
awk '/^  pull_request:$/ { print "  workflow_dispatch:" } { print }' "$WORKFLOW" > "$TMP/two-triggers.yml"
check "the second-trigger mutant differs" differs "$TMP/two-triggers.yml"
two_triggers() { test "$(triggers "$TMP/two-triggers.yml")" = pull_request; }
refute "a second trigger is noticed" two_triggers
sed 's/^  pull_request:$/  pull_request_target:/' "$WORKFLOW" > "$TMP/target.yml"
check "the _target mutant differs" differs "$TMP/target.yml"
target_only() { test "$(triggers "$TMP/target.yml")" = pull_request; }
refute "the _target trigger is noticed" target_only
check "it runs on pull requests into main" grep -qx '    branches: \[main\]' "$WORKFLOW"
# The activity types, exactly: a run follows every push to a pull request.
# types_ok <workflow>: one types: line, with exactly these types
types_ok() {
  [ "$(grep -c '^ *types: ' "$1")" -eq 1 ] && grep -qx '    types: \[opened, reopened, synchronize\]' "$1"
}
check "it runs when a pull request is opened, reopened or pushed to" types_ok "$WORKFLOW"
sed 's/^    types: \[opened, reopened, synchronize\]$/    types: [closed]/' "$WORKFLOW" > "$TMP/closed.yml"
check "the closed-types mutant differs" differs "$TMP/closed.yml"
refute "other activity types are noticed" types_ok "$TMP/closed.yml"
# Nothing may skip the job or let it pass a failure: a job skipped by a
# conditional reports success to a required check, and a failed step
# marked continue-on-error does not fail its job.
# never_skips <workflow>: no if: anywhere and no continue-on-error
never_skips() { ! grep -qE '^ *(- )?if:' "$1" && ! grep -q 'continue-on-error' "$1"; }
check "no conditional and no continue-on-error" never_skips "$WORKFLOW"
awk '{ print } /^  feature-check:$/ { print "    if: false" }' "$WORKFLOW" > "$TMP/job-if.yml"
check "the job-if mutant differs" differs "$TMP/job-if.yml"
refute "a conditional on the job is noticed" never_skips "$TMP/job-if.yml"
# step_mutant <line>: the workflow with the line added to the checks step
step_mutant() { awk -v step="      - name: $CHECKS" -v add="$1" '{ print } $0 == step { print add }' "$WORKFLOW"; }
step_mutant '        if: false' > "$TMP/step-if.yml"
check "the step-if mutant differs" differs "$TMP/step-if.yml"
refute "a conditional on the checks step is noticed" never_skips "$TMP/step-if.yml"
step_mutant '        continue-on-error: true' > "$TMP/continue.yml"
check "the continue-on-error mutant differs" differs "$TMP/continue.yml"
refute "continue-on-error on the checks step is noticed" never_skips "$TMP/continue.yml"
# SC2016: GitHub expressions, matched as text.
# shellcheck disable=SC2016
check "a newer run for a pull request replaces an older one" \
  grep -qxF '  group: feature-check-${{ github.ref }}' "$WORKFLOW"
check "the older run is cancelled" grep -qx '  cancel-in-progress: true' "$WORKFLOW"
# The required check is matched by the job's name.
check "the job's check name is feature-check" grep -qx '    name: feature-check' "$WORKFLOW"
check "the workflow is one job" test "$(count 'runs-on: ' "$WORKFLOW")" -eq 1
# Run scripts get bash with pipefail, as the tests below run them.
check "the run scripts use bash -eo pipefail" \
  test "$(awk '/^defaults:/ { d = 1; next } d && /^[^ ]/ { exit } d && /^    shell: bash$/ { print "yes" }' "$WORKFLOW")" = yes

# --- the checkout: the pull request's head, full history, no credentials
# checkout_with: the lines of the checkout step after its uses: line
checkout_with() { awk '/uses: actions\/checkout@/ { on = 1; next } on && /^ *- / { exit } on' "$WORKFLOW"; }
# shellcheck disable=SC2016
check "the checkout takes the pull request's head" \
  grep -qxE ' +ref: \$\{\{ github\.event\.pull_request\.head\.sha \}\}' <(checkout_with)
check "with full history" grep -qxE ' +fetch-depth: 0' <(checkout_with)
check "without keeping the token" grep -qxE ' +persist-credentials: false' <(checkout_with)
check "the fetch step fetches the pull-request refs" \
  grep -qF "'+refs/pull/*/head:refs/remotes/origin/pr/*'" <(run_script "$FETCH")
check "the checks step runs check-features.sh --base origin/main" \
  grep -qF 'check-features.sh" --base origin/main' <(run_script "$CHECKS")
check "the checks step runs check-walkthrough on HEAD" \
  grep -qF 'check-walkthrough" HEAD' <(run_script "$CHECKS")
# step_line <name>: the line of that step
step_line() { grep -nF -- "- name: $1" "$WORKFLOW" | cut -d : -f 1; }
in_order() {
  local f t c
  f=$(step_line "$FETCH") t=$(step_line "$TOOLCHAIN") c=$(step_line "$CHECKS")
  [ -n "$f" ] && [ -n "$t" ] && [ -n "$c" ] && [ "$f" -lt "$c" ] && [ "$t" -lt "$c" ]
}
check "the refs and the toolchain come before the checks" in_order

# --- the header: for public repositories, from D129 and D137
# header: the comment block above name:, as one line, so a phrase may wrap
header() { sed -n '/^name:/q; s/^# \{0,1\}//; p' "$WORKFLOW" | tr '\n' ' ' | tr -s ' '; }
# Only the check scripts come from the base; the rest of a pull request
# is trusted, since tier 1 does not guard against tampering (D59).
refute "the header does not claim a change cannot weaken its own check" \
  grep -qF 'cannot weaken its own check' <(header)
# A pull request can still delete the step from this file.
refute "the header does not say a pull request cannot switch the checks off" \
  grep -qF 'cannot switch them off' <(header)
# SC2016: the backticks are text in the header, matched literally.
# shellcheck disable=SC2016
for text in D129 D137 D133 'writes no job' 'refs/pull/' '.githooks/' 'install.sh --gate' 'required' \
  'editing them in the pull request does not switch them off' \
  'this workflow file, feature-checks.conf, the tests' 'D59 accepts that' \
  'in both places below: `branches: [main]` and `--base origin/main`' \
  'a skipped job counts as a success' 'Require branches to be up to date before merging' 'D141'; do
  check "the header names $text" grep -qF -- "$text" <(header)
done

# --- the run scripts, in a fresh clone of a bare remote
# The fake stack: a shell test command and setup = none, as in
# check-features.test.sh. new_project <dir> <remote>: a working
# repository and its empty bare remote; sets $dev and $remote
new_project() {
  dev=$1 remote=$2
  git init -q -b main "$dev"
  git init -q --bare -b main "$remote"
  git -C "$dev" remote add origin "$remote"
  mkdir -p "$dev/src"
  cat > "$dev/run-tests.sh" << 'EOF'
found=0
for p in "$@"; do
  while IFS= read -r t; do
    found=1
    bash "$t" < /dev/null || exit 1
  done < <(find "$p" -name '*.test.sh' | sort)
done
[ "$found" -eq 1 ]
EOF
  cat > "$dev/run-all.sh" << 'EOF'
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
  printf 'reports/\n' > "$dev/.gitignore"
  printf 'echo ""\n' > "$dev/src/greet.sh"
}
CONFIG='test_command = bash run-tests.sh {path}
setup = none
run = bash run-all.sh
count_file = .test-count
scan = e2e
timeout = 60
'
# install_checks: .ai-workflow/ and .githooks/, as a project commits them
install_checks() { bash "$ROOT/hooks/install.sh" --copy-only --gate "$dev" > /dev/null 2>&1; }
commit_all() { git -C "$dev" add -A && git -C "$dev" commit -q --no-verify -m "$1"; }
sha() { git -C "$dev" rev-parse HEAD; }
push_as() { git -C "$dev" push -q -f origin "HEAD:$1" 2> /dev/null; } # push_as <ref>
# feature_file <Level> <Walkthrough: line>: the greeting feature
feature_file() {
  mkdir -p "$dev/docs/features"
  {
    printf '# Feature F1: greeting\n\n'
    printf '| ID | Rev | Item | Entry point | Expected outcome | Level | Test |\n'
    printf '| --- | --- | --- | --- | --- | --- | --- |\n'
    printf '| F1-1 | 1 | greet | greet.sh | prints hello | %s | e2e/one.test.sh, F1-1-r1 |\n\n' "$1"
    printf 'Locked tests: e2e at %s\n\n%s\n' "$locked" "$2"
  } > "$dev/docs/features/greet.md"
}
# build_feature: on the branch checked out, the test writer's commit, the
# feature at Level wired, then the walkthrough at Level functional; sets
# $locked, $feat and $head
build_feature() {
  mkdir -p "$dev/e2e"
  # shellcheck disable=SC2016
  printf '# name: F1-1-r1 greets\nhere=$(dirname "$0")\n[ "$(bash "$here/../src/greet.sh")" = hello ]\n' \
    > "$dev/e2e/one.test.sh"
  commit_all "test: lock the greeting test"
  locked=$(sha)
  feature_file wired 'Walkthrough:'
  printf '%s' "$CONFIG" > "$dev/feature-checks.conf"
  printf '1 reports/all.xml\n' > "$dev/.test-count"
  printf 'echo hello\n' > "$dev/src/greet.sh"
  commit_all "feat: greet"
  feat=$(sha)
  feature_file functional "Walkthrough: done 2026-11-18 at $feat"
  commit_all "docs: record the walkthrough"
  head=$(sha)
}

# ci_at <commit>: a fresh clone of $remote at that commit, detached, as
# actions/checkout leaves it with fetch-depth: 0 (every branch and tag,
# no pull-request refs)
ci_at() {
  rm -rf "$TMP/ci"
  git clone -q --no-local "$remote" "$TMP/ci" 2> /dev/null &&
    git -C "$TMP/ci" checkout -q --detach "$1"
}
# step <name> <base> <head>: runs that step's script in the clone, with
# the environment GitHub gives it; its output in $TMP/step.out
step() {
  local script
  script=$(run_script "$1")
  if [ -z "$script" ]; then
    echo "no step '$1' in the workflow" > "$TMP/step.out"
    return 2
  fi
  (cd "$TMP/ci" && RUNNER_TEMP="$TMP/runner" TMPDIR="$TMP/tmpdir" PR_BASE=$2 PR_HEAD=$3 \
    bash --noprofile --norc -eo pipefail -c "$script") > "$TMP/step.out" 2>&1
}
# pr_ok <base> <head>: the job passes for a pull request from base to head
pr_ok() { ci_at "$2" && step "$FETCH" "$1" "$2" && step "$CHECKS" "$1" "$2"; }
says() { grep -qF -- "$1" "$TMP/step.out"; }
warnings() { grep -c '::warning::' "$TMP/step.out"; }
in_clone() { git -C "$TMP/ci" cat-file -e "$1^{commit}" 2> /dev/null; }

new_project "$TMP/dev" "$TMP/remote.git"
install_checks
commit_all "chore: start with the feature checks"
start=$(sha)
push_as refs/heads/main

# The toolchain step is the project's to fill in: until then it fails.
ci_at "$start"
refute "the toolchain step fails until it is filled in" step "$TOOLCHAIN" "$start" "$start"
check "it says to fill it in" says '::error::Fill in the toolchain step'

# 7. Nothing to check without docs/features/.
git -C "$dev" checkout -q -b readme
printf '# A project\n' > "$dev/README.md"
commit_all "docs: add a readme"
push_as refs/heads/readme
check "7. a pull request in a project without docs/features/ passes" pr_ok "$start" "$(sha)"
check "check-features.sh says there is nothing to check" says 'nothing to check'

# 1. A finished feature with a walkthrough and passing checks.
git -C "$dev" checkout -q -b feature "$start"
build_feature
good=$head
push_as refs/heads/feature
check "1. a functional feature with a walkthrough and passing checks passes" pr_ok "$start" "$good"
check "the feature checks ran and passed" says 'every feature check passed'
check "with the base's copies, so no warning" test "$(warnings)" -eq 0

# The checks run on the pull request's head, never on another commit.
checks_at() { ci_at "$1" && step "$CHECKS" "$2" "$3"; } # checks_at <checkout> <base> <head>
refute "a checkout that is not the pull request's head fails" checks_at "$feat" "$start" "$good"
check "it says the checkout is not the head" says "not the pull request's head"
lost=1234567890123456789012345678901234567890
refute "a base that is not in the clone fails" checks_at "$good" "$lost" "$good"
check "it names the base" says "$lost"

# 2. The same with an empty Walkthrough: line.
feature_file functional 'Walkthrough:'
commit_all "docs: drop the walkthrough"
push_as refs/heads/no-walk
refute "2. the same with an empty Walkthrough: line fails" pr_ok "$start" "$(sha)"
check "it names the walkthrough check" says '::error::The walkthrough check failed'
check "check-walkthrough says why" says 'the walkthrough is not recorded'
check "the feature checks still passed" says 'every feature check passed'
refute "they are not blamed" says '::error::The feature checks failed'
no_walk=$(sha)

# 4. The walkthrough check comes from the base: switching it off in the
# pull request does not help.
printf '#!/usr/bin/env bash\nexit 0\n' > "$dev/.githooks/check-walkthrough"
commit_all "chore: switch the walkthrough check off"
push_as refs/heads/no-walk
refute "4. the same, with check-walkthrough switched off in the pull request, still fails" \
  pr_ok "$start" "$(sha)"
check "the base's check-walkthrough found it" says 'the walkthrough is not recorded'
git -C "$dev" reset -q --hard "$no_walk"

# 3. Feature checks that fail: the locked test was edited.
git -C "$dev" reset -q --hard "$good"
printf 'true\n' >> "$dev/e2e/one.test.sh"
commit_all "fix: weaken the locked test"
weak=$(sha)
push_as refs/heads/weak
refute "3. a pull request whose feature checks fail fails" pr_ok "$start" "$weak"
check "it names the feature checks" says '::error::The feature checks failed'
check "check-locked-tests.sh names the test" says 'changed: e2e/one.test.sh'
refute "the walkthrough check is not blamed" says '::error::The walkthrough check failed'

# 4. The feature checks come from the base, the checks they run too.
for script in check-features.sh check-locked-tests.sh; do
  git -C "$dev" reset -q --hard "$weak"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$dev/.ai-workflow/$script"
  commit_all "chore: switch $script off"
  push_as refs/heads/weak
  refute "4. the same, with .ai-workflow/$script switched off in the pull request, still fails" \
    pr_ok "$start" "$(sha)"
  check "the base's checks found the edit ($script)" says 'changed: e2e/one.test.sh'
done

# 5. A pull request that adds the checks is checked with its own copies,
# with a warning.
new_project "$TMP/fresh" "$TMP/fresh.git"
commit_all "chore: start"
fresh_start=$(sha)
push_as refs/heads/main
git -C "$dev" checkout -q -b readme
printf '# A project\n' > "$dev/README.md"
commit_all "docs: add a readme"
push_as refs/heads/readme
refute "no checks in the base or the pull request: fails" pr_ok "$fresh_start" "$(sha)"
check "it says .ai-workflow/ is missing" says '::error::.ai-workflow/check-features.sh is missing'
git -C "$dev" checkout -q -b feature "$fresh_start"
install_checks
commit_all "chore: add the feature checks"
build_feature
push_as refs/heads/feature
check "5. a pull request that adds the checks passes with its own copies" pr_ok "$fresh_start" "$head"
check "it warns that .ai-workflow/ is new" \
  says '::warning::.ai-workflow/check-features.sh is new in this pull request'
check "it warns that check-walkthrough is new" \
  says '::warning::.githooks/check-walkthrough is new in this pull request'
check "the copies ran" says 'every feature check passed'
feature_file functional 'Walkthrough:'
commit_all "docs: drop the walkthrough"
push_as refs/heads/feature
refute "5. its own copies still fail an empty walkthrough" pr_ok "$fresh_start" "$(sha)"
check "check-walkthrough says why" says 'the walkthrough is not recorded'

# 6. After a squash merge deletes a feature's branch, its locked commit
# and the commit its walkthrough names live only on refs/pull/<n>/head.
new_project "$TMP/squash" "$TMP/squash.git"
install_checks
commit_all "chore: start with the feature checks"
push_as refs/heads/main
git -C "$dev" checkout -q -b old
build_feature
push_as refs/heads/old
push_as refs/pull/1/head
old_locked=$locked old_feat=$feat
git -C "$dev" checkout -q main
git -C "$dev" merge -q --squash old > /dev/null 2>&1
commit_all "feat: greet (#1)"
merged=$(sha)
push_as refs/heads/main
git -C "$dev" push -q origin :old 2> /dev/null
git -C "$dev" checkout -q -b next
printf '# A project\n' > "$dev/README.md"
commit_all "docs: add a readme"
next=$(sha)
push_as refs/heads/next
push_as refs/pull/2/head
ci_at "$next"
refute "6. the locked commit is not in a fresh clone" in_clone "$old_locked"
refute "nor the commit the walkthrough names" in_clone "$old_feat"
refute "without the pull-request refs the checks fail" step "$CHECKS" "$merged" "$next"
check "check-walkthrough cannot find the commit it names" says 'not found in this repository'
check "the fetch step passes" step "$FETCH" "$merged" "$next"
check "it brings the locked commit" in_clone "$old_locked"
check "and the commit the walkthrough names" in_clone "$old_feat"
check "6. with the pull-request refs the checks pass" step "$CHECKS" "$merged" "$next"
check "the feature checks ran and passed" says 'every feature check passed'

finish
