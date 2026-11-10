#!/usr/bin/env bash
# Tests for the templates that must stay in step with the hook.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

HOOK="$ROOT/hooks/commit-msg"
COMMITLINT="$ROOT/templates/commitlint.config.mjs"

# --- commitlint.config.mjs: same types and limit as the hook
hook_types() { sed -n "s/^types='\(.*\)'$/\1/p" "$HOOK"; }
hook_max() { sed -n 's/^max=\([0-9]*\)$/\1/p' "$HOOK"; }
config_types() {
  sed -n 's/^const types = \[\(.*\)\];$/\1/p' "$1" | tr -d "' " | tr ',' '|'
}
config_max() { sed -n 's/^const max = \([0-9]*\);$/\1/p' "$1"; }
matches_hook() { # matches_hook <commitlint config>
  [ -n "$(hook_types)" ] && [ "$(config_types "$1")" = "$(hook_types)" ] &&
    [ -n "$(hook_max)" ] && [ "$(config_max "$1")" = "$(hook_max)" ]
}
check "commitlint config has the hook's types and limit" matches_hook "$COMMITLINT"
sed "s/'revert'\]/'revert', 'style']/" "$COMMITLINT" > "$TMP/drift-types.mjs"
refute "a drifted type list is noticed" matches_hook "$TMP/drift-types.mjs"
sed 's/^const max = 72;$/const max = 100;/' "$COMMITLINT" > "$TMP/drift-max.mjs"
refute "a drifted limit is noticed" matches_hook "$TMP/drift-max.mjs"
for rule in "'subject-case': \[0\]" "'body-max-line-length': \[0\]" "'footer-max-line-length': \[0\]" \
  "'ai-workflow/subject-length': \[2, 'always', max\]" "'header-max-length': \[0\]" \
  "defaultIgnores: false"; do
  check "commitlint config sets $rule" grep -q "$rule" "$COMMITLINT"
done

# --- commit-check.yml: hardened, and its scripts do what they say
WORKFLOW="$ROOT/templates/commit-check.yml"
count() { grep -c -- "$1" "$2"; }
hardened() { # hardened <workflow>
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
check "commit-check.yml is hardened" hardened "$WORKFLOW"
sed 's/@3d3c42e5aac5ba805825da76410c181273ba90b1/@v7/' "$WORKFLOW" > "$TMP/unpinned.yml"
refute "an unpinned action is noticed" hardened "$TMP/unpinned.yml"
# SC2016: sed inserts a literal expression.
# shellcheck disable=SC2016
sed 's/"\$RUNNER_TEMP\/pr-title"$/"${{ github.event.pull_request.title }}"/' \
  "$WORKFLOW" > "$TMP/inject.yml"
check "the injection mutant differs from the workflow" test -n "$(diff "$WORKFLOW" "$TMP/inject.yml")"
refute "an expression inside a run script is noticed" hardened "$TMP/inject.yml"
grep -v 'timeout-minutes' "$WORKFLOW" > "$TMP/no-timeout.yml"
refute "a job without a timeout is noticed" hardened "$TMP/no-timeout.yml"

# run_script <step name>: the run block of that step, dedented
run_script() {
  awk -v step="- name: $1" '
    index($0, step) { found = 1; next }
    found && /^ *run: \|/ { indent = index($0, "r") + 2; inrun = 1; next }
    inrun && NF && substr($0, 1, indent - 1) ~ /[^ ]/ { exit }
    inrun { print substr($0, indent) }
  ' "$WORKFLOW"
}

repo="$TMP/project"
git init -q -b main "$repo"
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.com
git -C "$repo" config core.autocrlf false
mkdir -p "$repo/.githooks" "$TMP/runner"
cp "$HOOK" "$repo/.githooks/commit-msg"
cp "$ROOT/hooks/check-commits" "$repo/.githooks/check-commits"
printf '#!/bin/sh\ntouch "$PWD/pre-push-ran"\n' > "$repo/.githooks/pre-push"
commit() { # commit <message with escapes>: a commit the local hook never saw
  echo "$1" >> "$repo/file" && git -C "$repo" add file &&
    git -C "$repo" commit -q --no-verify --allow-empty -m "$(printf '%b' "$1")"
}
git -C "$repo" add .githooks
commit "chore: start"
base=$(git -C "$repo" rev-parse HEAD)
title_ok() { # title_ok <title> [pr number]: the title step passes for a PR $base..HEAD
  (cd "$repo" && RUNNER_TEMP="$TMP/runner" TITLE=$1 PR_NUMBER=${2:-123} \
    PR_BASE=$base PR_HEAD=$(git rev-parse HEAD) \
    env -u GIT_EDITOR bash -eo pipefail -c "$(run_script 'The PR title follows the commit format')") \
    > "$TMP/step.out" 2>&1
}
check "title step: the script is found" test -n "$(run_script 'The PR title follows the commit format')"
check "title step: a conventional title passes" title_ok "feat(api): add the export endpoint"
refute "title step: a plain title fails" title_ok "Add the export endpoint"
refute "title step: a long title fails" title_ok "fix: $(printf '%070d' 0 | tr 0 x)"
# A squash merge appends " (#N)" to the title; the subject on main must still fit.
check "title step: 65 characters plus ' (#123)' pass" title_ok "fix: $(printf '%060d' 0 | tr 0 x)"
refute "title step: 66 characters plus ' (#123)' fail" title_ok "fix: $(printf '%061d' 0 | tr 0 x)"
refute "title step: 64 characters plus ' (#12345)' fail" title_ok "fix: $(printf '%059d' 0 | tr 0 x)" 12345
refute "title step: '#42 fix login' fails" title_ok "#42 fix login"
# A PR title is never a message git wrote, so the hook's exemptions do not apply.
for title in "Merge branch 'main' into login" "Merge branches 'a' and 'b'" \
  "Merge remote-tracking branch 'origin/main'" "Merge pull request #12 from a/b" \
  "Merge tag 'v1.2.0'" "Merge commit 'abc1234'" 'Revert "feat: add login"' \
  'Reapply "feat: add login"' "fixup! feat: add login" "squash! feat: add login" \
  "amend! feat: add login"; do
  refute "title step: '$title' fails" title_ok "$title"
done
hook_exemptions() {
  # SC2016: $subject is text in the hook, matched literally.
  # shellcheck disable=SC2016
  sed -n '/^case \$subject in/,/exit 0 ;;/p' "$HOOK" | grep -oE "\"[^\"]+\"\*|'[^']+'\*"
}
exemptions_in_sync() {
  local p
  [ "$(hook_exemptions | wc -l)" -ge 10 ] || return 1
  while IFS= read -r p; do grep -qF -- "$p" "$WORKFLOW" || return 1; done < <(hook_exemptions)
}
check "title step rejects every subject the hook exempts" exemptions_in_sync
# SC2016: the title must stay unexpanded.
# shellcheck disable=SC2016
check "title step: a title with \$(...) or backticks is only text" title_ok 'feat: $(touch pwned) `touch pwned`'
check "title step: nothing was run from the title" test ! -e "$repo/pwned"

# --- the commits step: every commit of a PR or a push, checked by the hook
# as it was before the change
commit "feat: add the export"
commit "fix: handle an empty export"
COMMITS_STEP=$(run_script 'Every commit follows the commit format')
check "commits step: the script is found" test -n "$COMMITS_STEP"
check "CI never names a project's pre-push hook" test "$(grep -c 'githooks/pre-push' "$WORKFLOW")" -eq 0
# commits_ok <event> [before]: the step passes for a pull request from
# $base to HEAD, or for a push from <before> (default $base) to HEAD
commits_ok() {
  (cd "$repo" && RUNNER_TEMP="$TMP/runner" EVENT=$1 \
    PR_BASE=$base PR_HEAD=$(git rev-parse HEAD) \
    PUSH_BEFORE=$(if [ "$1" = push ]; then echo "${2:-$base}"; fi) PUSH_AFTER=$(git rev-parse HEAD) \
    env -u GIT_EDITOR bash -eo pipefail -c "$COMMITS_STEP") > "$TMP/step.out" 2>&1
}
tip=$(git -C "$repo" rev-parse HEAD)
reset_tip() { git -C "$repo" reset -q --hard "$tip"; }

check "PR: good commits pass" commits_ok pull_request
check "push: good commits pass" commits_ok push
for subject in "fixup! feat: add the export" "squash! feat: add the export" \
  "amend! feat: add the export" "WIP" "add stuff." "# note\nfeat: add a kept comment line"; do
  commit "$subject"
  refute "PR: a '$subject' commit fails" commits_ok pull_request
  refute "push: a '$subject' commit fails" commits_ok push
  reset_tip
done

# A bad commit in the middle is caught, not just the newest one.
commit "WIP"
commit "feat: a good commit on top"
refute "PR: a bad commit below a good one fails" commits_ok pull_request
check "the failure names the bad commit" grep -q "$(git -C "$repo" rev-parse HEAD~1)" "$TMP/step.out"
reset_tip

# Merge commits that git writes pass, as in the hook.
git -C "$repo" checkout -q -b side
commit "feat: work on a side branch"
git -C "$repo" checkout -q main
commit "fix: work on main meanwhile"
git -C "$repo" merge -q --no-ff --no-verify --no-edit side > /dev/null 2>&1
check "PR: a merge commit git wrote passes" commits_ok pull_request
reset_tip

# A change cannot weaken its own check: the hook comes from the base.
printf '#!/bin/sh\nexit 0\n' > "$repo/.githooks/commit-msg"
git -C "$repo" add .githooks
commit "WIP: switch the hook off"
refute "PR: a commit that disables the hook is checked by the old one" commits_ok pull_request
refute "push: the same, with the hook from before the push" commits_ok push
reset_tip

# A new branch (all-zero before) or a before that is gone: the head only.
zero=0000000000000000000000000000000000000000
commit "WIP"
commit "feat: a good head"
check "push from nothing: only the head is checked" commits_ok push "$zero"
check "it says so" grep -q 'checking' "$TMP/step.out"
check "push from a lost commit: only the head is checked" commits_ok push 1234567890123456789012345678901234567890
reset_tip
commit "WIP"
refute "push from nothing: a bad head fails" commits_ok push "$zero"
reset_tip

# A force push: only the commits that are new on top of the old tip count.
git -C "$repo" checkout -q -b old "$base"
commit "WIP never pushed again"
old=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" checkout -q main
check "force push: the commits replacing the old tip pass" commits_ok push "$old"
commit "WIP"
refute "force push: a bad new commit fails" commits_ok push "$old"
reset_tip

# The workflow may land in the change that first commits the hook: the
# base has none, so the change's own hook is used, with a warning.
main_repo=$repo main_base=$base
new_project() { # new_project <dir>: $repo with one commit and no hook
  repo=$1
  git init -q -b main "$repo"
  git -C "$repo" config user.name test
  git -C "$repo" config user.email test@example.com
  git -C "$repo" config core.autocrlf false
  commit "chore: start"
  base=$(git -C "$repo" rev-parse HEAD)
}
new_project "$TMP/fresh"
mkdir -p "$repo/.githooks"
cp "$HOOK" "$repo/.githooks/commit-msg"
cp "$ROOT/hooks/check-commits" "$repo/.githooks/check-commits"
printf '#!/bin/sh\ntouch "$PWD/pre-push-ran"\n' > "$repo/.githooks/pre-push"
git -C "$repo" add .githooks
commit "ci: add the commit hook"
check "first hook: the title is checked with the PR's own hook" title_ok "ci: add the commit check"
check "first hook: the title step warns" grep -q '::warning::' "$TMP/step.out"
refute "first hook: a bad title still fails" title_ok "Add the commit check"
check "first hook: the commits are checked with the PR's own hook" commits_ok pull_request
check "first hook: the commits step warns" grep -q '::warning::' "$TMP/step.out"
check "first hook: the same on a push" commits_ok push
commit "WIP"
refute "first hook: a bad commit still fails" commits_ok pull_request
new_project "$TMP/nohook"
commit "feat: no hook anywhere"
refute "no hook at all: the title step fails" title_ok "feat: add something"
refute "no hook at all: the commits step fails" commits_ok pull_request

# A force push whose old tip is no longer in the clone: the old tip is
# fetched so its hook checks the push; when it cannot be fetched, only the
# head is checked, with the pushed hook and a warning.
repo=$main_repo base=$main_base
git init -q --bare -b main "$TMP/remote.git"
git -C "$TMP/remote.git" config uploadpack.allowAnySHA1InWant true
git -C "$repo" remote add origin "$TMP/remote.git"
git -C "$repo" push -q origin main 2> /dev/null
git -C "$repo" checkout -q -b lost
commit "chore: the old tip"
old=$(git -C "$repo" rev-parse HEAD)
git -C "$repo" push -q origin lost 2> /dev/null
git -C "$repo" push -q origin :lost 2> /dev/null
git -C "$repo" checkout -q main
printf '#!/bin/sh\nexit 0\n' > "$repo/.githooks/commit-msg"
git -C "$repo" add .githooks
commit "WIP: switch the hook off"
git -C "$repo" push -q -f origin main 2> /dev/null
git clone -q --no-local "$TMP/remote.git" "$TMP/ci" 2> /dev/null
git -C "$repo" reset -q --hard "$tip"
repo="$TMP/ci"
no_lost_tip() { git -C "$repo" cat-file -e "$old^{commit}" 2> /dev/null; }
refute "lost tip: it is not in the fresh clone" no_lost_tip
refute "lost tip: fetched, and its hook rejects the push" commits_ok push "$old"
check "lost tip that cannot be fetched: only the head, with a warning" \
  commits_ok push 1234567890123456789012345678901234567890
check "it warns that the pushed hook was used" grep -q '::warning::' "$TMP/step.out"
repo=$main_repo base=$main_base

# A scheduled or manual run checks the commits of the last eight days on
# the branch, with the hook from the commit just before them.
repo="$TMP/scheduled"
git init -q -b main "$repo"
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.com
git -C "$repo" config core.autocrlf false
mkdir -p "$repo/.githooks"
cp "$HOOK" "$repo/.githooks/commit-msg"
cp "$ROOT/hooks/check-commits" "$repo/.githooks/check-commits"
printf '#!/bin/sh\ntouch "$PWD/pre-push-ran"\n' > "$repo/.githooks/pre-push"
git -C "$repo" add .githooks
days_ago() { printf '%s +0000' "$(($(date +%s) - $1 * 86400))"; }
GIT_AUTHOR_DATE=$(days_ago 30) GIT_COMMITTER_DATE=$(days_ago 30) commit "chore: start"
GIT_AUTHOR_DATE=$(days_ago 20) GIT_COMMITTER_DATE=$(days_ago 20) commit "WIP from before the rules"
commit "feat: this week's work"
check "schedule: a bad commit older than the window is not checked" commits_ok schedule
check "workflow_dispatch: the same window" commits_ok workflow_dispatch
commit "WIP this week"
commit "fix: a good commit on top"
refute "schedule: a bad commit in the window fails" commits_ok schedule
refute "workflow_dispatch: the same" commits_ok workflow_dispatch

# The triggers: pull requests, pushes to main, by hand, one run per ref.
check "commit-check runs by hand" grep -qx '  workflow_dispatch:' "$WORKFLOW"
check "commit-check cancels a superseded run" grep -qx '  cancel-in-progress: true' "$WORKFLOW"
check "commit-check offers a schedule for private repos" grep -q '^  #   - cron: ' "$WORKFLOW"
repo=$main_repo base=$main_base

# --- dependabot.yml: valid YAML, every two weeks, titles that pass the hook
DEPENDABOT="$ROOT/templates/dependabot.yml"
uncommented() { sed 's/^#  /  /' "$DEPENDABOT"; } # with the placeholders switched on
sed 's/^#  /  /' "$DEPENDABOT" > "$TMP/dependabot.all.yml"
yaml_ok() { # yaml_ok <file>: parses with yq or PyYAML; status 2 when neither exists
  if command -v yq > /dev/null 2>&1; then
    yq eval '.' "$1" > /dev/null 2>&1
  elif python3 -c 'import yaml' > /dev/null 2>&1; then
    python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$1" > /dev/null 2>&1
  else
    return 2
  fi
}
yaml_ok "$DEPENDABOT"
case $? in
  0) pass ;;
  2) printf 'templates.test.sh: SKIP: no YAML parser (yq or PyYAML) to parse dependabot.yml\n' ;;
  *) fail "dependabot.yml parses as YAML" ;;
esac
yaml_ok "$TMP/dependabot.all.yml"
case $? in 0) pass ;; 2) ;; *) fail "dependabot.yml with the placeholders on parses" ;; esac
check "the placeholders cover npm and pip" \
  test "$(uncommented | grep -cE '^  - package-ecosystem: (npm|pip)$')" -eq 2
check "github-actions is on" grep -qx '  - package-ecosystem: github-actions' "$DEPENDABOT"
entries=$(uncommented | grep -c '^  - package-ecosystem: ')
check "every ecosystem runs on the 1st and 15th" \
  test "$(uncommented | grep -c "cronjob: '0 6 1,15 \* \*'")" -eq "$entries"
check "every ecosystem has a commit-message prefix" \
  test "$(uncommented | grep -c '^      prefix: ')" -eq "$entries"
check "every ecosystem has a groups block" test "$(uncommented | grep -c '^    groups:$')" -eq "$entries"
# Groups apply to version updates by default; security updates need their
# own group or each arrives as an ungrouped PR with a long title.
check "every ecosystem groups its version updates" \
  test "$(uncommented | grep -c '^        applies-to: version-updates$')" -eq "$entries"
check "every ecosystem groups its security updates" \
  test "$(uncommented | grep -c '^        applies-to: security-updates$')" -eq "$entries"
# Dependabot's grouped title: "<prefix>: bump the <group> group across 1
# directory with <n> updates", and a squash merge appends " (#<PR>)".
# Each must pass the hook at a large n and PR number.
group_titles() { # one "<prefix> <group>" line per group, per ecosystem
  uncommented | awk '
    /^  - package-ecosystem: / { flush(); n = 0; prefix = "" }
    /^      [a-z-]+:$/ { sub(/^ +/, ""); sub(/:$/, ""); groups[++n] = $0 }
    /^      prefix: / { prefix = $2 }
    function flush(i) { for (i = 1; i <= n; i++) print prefix, groups[i] }
    END { flush() }
  '
}
titles_pass() {
  local prefix group
  [ -n "$(group_titles)" ] || return 1
  while read -r prefix group; do
    printf '%s: bump the %s group across 1 directory with 99 updates (#9999)\n' \
      "$prefix" "$group" > "$TMP/title"
    GIT_EDITOR=: bash "$HOOK" "$TMP/title" > /dev/null 2>&1 || return 1
  done < <(group_titles)
}
check "every grouped Dependabot title passes the hook after a squash merge" titles_pass
sed 's/prefix: ci$/prefix: deps/' "$DEPENDABOT" > "$TMP/bad-prefix.yml"
bad_titles() { DEPENDABOT="$TMP/bad-prefix.yml" titles_pass; }
refute "a prefix that is not a commit type is noticed" bad_titles
sed 's/^      actions:$/      github-actions-updates:/' "$DEPENDABOT" > "$TMP/long-group.yml"
long_group() { DEPENDABOT="$TMP/long-group.yml" titles_pass; }
refute "a group name too long for the subject is noticed" long_group

refute "CI never ran a project's pre-push hook" test -e "$TMP/project/pre-push-ran"

finish
