#!/usr/bin/env bash
# Table test for hooks/commit-msg: each row is a message the hook must
# accept (ok) or reject (bad). Messages use printf %b escapes (\n, \r).
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

HOOK="$ROOT/hooks/commit-msg"

# run_hook <message with escapes>: exit status of the hook on that message
run_hook() {
  printf '%b' "$1" > "$TMP/COMMIT_EDITMSG"
  bash "$HOOK" "$TMP/COMMIT_EDITMSG" > "$TMP/out" 2>&1
}

expect() {
  local want=$1 msg=$2
  if run_hook "$msg"; then got=ok; else got=bad; fi
  if [ "$got" = "$want" ]; then
    pass
  else
    fail "expected $want, got $got: $msg"
    sed 's/^/    /' "$TMP/out" >&2
  fi
}

# Format: expectation|message
while IFS='|' read -r want msg; do
  case $want in ''|'#'*) continue ;; esac
  expect "$want" "$msg"
done <<'TABLE'
# Plain subjects
ok|feat: add login form
ok|fix(auth): reject expired tokens
ok|feat(api)!: drop the v1 endpoints
ok|refactor!: rename config keys
ok|build(deps-dev): bump vitest to 3.2
ok|ci(release/v2): pin the checkout action
ok|revert: undo the cache warm-up change
# Bodies and footers
ok|docs: explain the setup step\n\nNew contributors kept missing step two.
ok|fix(parser): handle empty input\n\nThe parser crashed on an empty file.\n\nRefs: R99\nCo-Authored-By: Someone <someone@example.com>
# What git strips before saving the message
ok|\n\nfeat: add login form
ok|feat: add login form
ok|feat: add login form\n# Please enter the commit message for your changes.\n# Lines starting with '#' will be ignored.
ok|feat: add login form\n# ------------------------ >8 ------------------------\ndiff --git a/x b/x
ok|feat: add login form\r\n\r\nWritten in an editor that saves CRLF.\r\n
# Messages git writes itself
ok|Merge branch 'main' into feature/login
ok|Merge remote-tracking branch 'origin/main'
ok|Merge pull request #12 from someone/login
ok|Merge tag 'v1.2.0'
ok|Revert "feat: add login form"\n\nThis reverts commit 1234567.
ok|fixup! feat: add login form
ok|squash! fix(auth): reject expired tokens
ok|amend! feat: add login form
# Rejected
bad|
bad|# only a comment
bad|add login form
bad|feature: add login form
bad|style: format the code
bad|Feat: add login form
bad|FIX: reject expired tokens
bad|feat:add login form
bad|feat add login form
bad|feat:
bad|feat:  add login form
bad|feat(): add login form
bad|feat(API): add login form
bad|feat(my scope): add login form
bad|feat(api)(web): add login form
bad|feat!(api): add login form
bad|feat: add login form.
bad|feat: add login form\nThe body starts without a blank line.
bad|Merge my changes
bad|Revert the login form
bad|fixup!feat: add login form
bad|WIP
TABLE

# Subject length: 72 characters is the limit.
pad() {
  local s=''
  while [ "${#s}" -lt "$1" ]; do s="${s}x"; done
  printf '%s' "$s"
}
expect ok "feat: $(pad 66)"
expect bad "feat: $(pad 67)"
expect ok "fix(scope): $(pad 60)"
expect bad "fix(scope): $(pad 61)"

# Every allowed type passes; the rejection message names the rules.
for type in feat fix docs test refactor perf build ci chore revert; do
  expect ok "$type: do one thing"
done
run_hook "oops"
check "rejection message lists the allowed types" grep -q 'feat, fix, docs' "$TMP/out"

finish
