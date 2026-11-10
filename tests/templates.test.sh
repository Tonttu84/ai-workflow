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
sed 's/bash .githooks\/commit-msg "\$RUNNER_TEMP/bash .githooks\/commit-msg "${{ github.event.pull_request.title }}/' \
  "$WORKFLOW" > "$TMP/inject.yml"
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
title_ok() { # title_ok <title>: the title step passes in $repo
  (cd "$repo" && RUNNER_TEMP="$TMP/runner" TITLE=$1 env -u GIT_EDITOR bash -eo pipefail -c "$(run_script 'The PR title follows the commit format')") \
    > /dev/null 2>&1
}
check "title step: the script is found" test -n "$(run_script 'The PR title follows the commit format')"
check "title step: a conventional title passes" title_ok "feat(api): add the export endpoint"
refute "title step: a plain title fails" title_ok "Add the export endpoint"
refute "title step: a long title fails" title_ok "fix: $(printf '%070d' 0 | tr 0 x)"
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
commit() { # commit <message with escapes>: a commit the local hook never saw
  echo "$1" >> "$repo/file" && git -C "$repo" add file &&
    git -C "$repo" commit -q --no-verify --allow-empty -m "$(printf '%b' "$1")"
}
git -C "$repo" add .githooks
commit "chore: start"
base=$(git -C "$repo" rev-parse HEAD)
commit "feat: add the export"
commit "fix: handle an empty export"
COMMITS_STEP=$(run_script 'Every commit follows the commit format')
check "commits step: the script is found" test -n "$COMMITS_STEP"
# commits_ok <event> [before]: the step passes for a pull request from
# $base to HEAD, or for a push from <before> (default $base) to HEAD
commits_ok() {
  (cd "$repo" && RUNNER_TEMP="$TMP/runner" EVENT=$1 \
    PR_BASE=$base PR_HEAD=$(git rev-parse HEAD) \
    PUSH_BEFORE=${2:-$base} PUSH_AFTER=$(git rev-parse HEAD) \
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

finish
