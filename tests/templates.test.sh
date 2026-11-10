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
  "'header-max-length': \[2, 'always', max\]" "defaultIgnores: false"; do
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
  (cd "$repo" && RUNNER_TEMP="$TMP/runner" TITLE=$1 bash -eo pipefail -c "$(run_script 'The PR title follows the commit format')") \
    > /dev/null 2>&1
}
check "title step: the script is found" test -n "$(run_script 'The PR title follows the commit format')"
check "title step: a conventional title passes" title_ok "feat(api): add the export endpoint"
refute "title step: a plain title fails" title_ok "Add the export endpoint"
refute "title step: a long title fails" title_ok "fix: $(printf '%070d' 0 | tr 0 x)"
refute "title step: '#42 fix login' fails" title_ok "#42 fix login"
# SC2016: the title must stay unexpanded.
# shellcheck disable=SC2016
check "title step: a title with \$(...) or backticks is only text" title_ok 'feat: $(touch pwned) `touch pwned`'
check "title step: nothing was run from the title" test ! -e "$repo/pwned"

commit() { echo "$1" >> "$repo/file" && git -C "$repo" add file && git -C "$repo" commit -q --no-verify -m "$1"; }
commit "chore: start"
base=$(git -C "$repo" rev-parse HEAD)
commit "feat: add the export"
commit "fix: handle an empty export"
commits_ok() { # commits_ok: the commits step passes for $base..HEAD
  (cd "$repo" && BASE_SHA=$base HEAD_SHA=$(git rev-parse HEAD) bash -eo pipefail -c "$(run_script 'No fixup!, squash! or amend! commits')") \
    > /dev/null 2>&1
}
check "commits step: ordinary commits pass" commits_ok
for subject in "fixup! feat: add the export" "squash! feat: add the export" "amend! feat: add the export"; do
  git -C "$repo" branch -f before HEAD
  commit "$subject"
  refute "commits step: '${subject%% *}' commit fails" commits_ok
  git -C "$repo" reset -q --hard before
done

finish
