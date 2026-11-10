#!/usr/bin/env bash
# Table test for hooks/commit-msg: each row is a message the hook must
# accept (ok) or reject (bad). Messages use printf %b escapes (\n, \r).
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

HOOK="$ROOT/hooks/commit-msg"

# run_hook <message with escapes> [editor]: exit status of the hook on
# that message. Git exports GIT_EDITOR=: to the hook when no editor ran
# (-m, -F); "editor" runs it as after git's editor, with GIT_EDITOR unset.
run_hook() {
  printf '%b' "$1" > "$TMP/COMMIT_EDITMSG"
  if [ "${2-}" = editor ]; then
    env -u GIT_EDITOR bash "$HOOK" "$TMP/COMMIT_EDITMSG" > "$TMP/out" 2>&1
  else
    GIT_EDITOR=: bash "$HOOK" "$TMP/COMMIT_EDITMSG" > "$TMP/out" 2>&1
  fi
}

# expect <ok|bad>[@editor] <message with escapes>
expect() {
  local want=${1%@*} mode=${1#*@} msg=$2
  if run_hook "$msg" "$mode"; then got=ok; else got=bad; fi
  if [ "$got" = "$want" ]; then
    pass
  else
    fail "expected $want, got $got: $msg"
    sed 's/^/    /' "$TMP/out" >&2
  fi
}

# Format: expectation[@editor]|message
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
ok@editor|feat: add login form\n# ------------------------ >8 ------------------------\ndiff --git a/x b/x
# Comment lines: git drops them from a message written in its editor...
ok@editor|feat: add login form\n\n# Please enter the commit message for your changes. Lines starting\n# with '#' will be ignored, and an empty message aborts the commit.\n#\n# On branch main
ok@editor|# typed in the editor\nfeat: add login form\n\n# Please enter the commit message for your changes. Lines starting\n# with '#' will be ignored, and an empty message aborts the commit.
ok@editor|# typed in the editor\nfeat: add login form\n\n# ------------------------ >8 ------------------------\n# Do not modify or remove the line above.\ndiff --git a/x b/x
bad@editor|# typed in the editor\nfeat: add login form\n\n# Please enter the commit message for your changes. Lines starting\n# with '#' will be kept; you may remove them yourself if you want to.
# ...also when git's template is translated or switched off (--no-status)
ok@editor|# Notiz\nfeat: add login form\n\n# Bitte geben Sie eine Commit-Beschreibung ein.
ok@editor|# typed in the editor\nfeat: add login form
# ...but keeps them in a message given with -m or -F
bad|# anything\nfeat: add login form
bad|#WIP hack\n\nfeat: add login form
bad|feat: add login form\n#42
bad|# Notiz\nfeat: add login form\n\n# Bitte geben Sie eine Commit-Beschreibung ein.
bad|feat: add login form\n# ------------------------ >8 ------------------------\ndiff --git a/x b/x
ok|feat: add login form\n\n#42 was the cause
ok|feat: add login form\r\n\r\nWritten in an editor that saves CRLF.\r\n
# Messages git writes itself
ok|Merge branch 'main' into feature/login
ok|Merge remote-tracking branch 'origin/main'
ok|Merge pull request #12 from someone/login
ok|Merge tag 'v1.2.0'
ok|Merge branches 'a' and 'b'
ok|Merge commit 'abc1234'
ok|Revert "feat: add login form"\n\nThis reverts commit 1234567.
ok|Reapply "feat: add login form"\n\nThis reverts commit 89abcde.
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
bad|Reapply the login form
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

# The limit counts characters, not bytes, in any locale.
pad_utf8() { # pad_utf8 <n> [char]: n copies of a two-byte character
  local i c=${2:-'\303\244'} # a-umlaut by default
  for ((i = 0; i < $1; i++)); do printf '%b' "$c"; done
}
expect_c() { # expect under LC_ALL=C
  local want=$1 msg=$2 got
  printf '%s' "$msg" > "$TMP/COMMIT_EDITMSG"
  if GIT_EDITOR=: LC_ALL=C bash "$HOOK" "$TMP/COMMIT_EDITMSG" > "$TMP/out" 2>&1; then got=ok; else got=bad; fi
  if [ "$got" = "$want" ]; then pass; else fail "LC_ALL=C: expected $want, got $got: $msg"; fi
}
expect_c ok "fix: $(pad_utf8 60)"
expect_c ok "fix: $(pad_utf8 67)"
expect_c bad "fix: $(pad_utf8 68)"
check "the length is reported in characters" grep -q 'is 73 characters' "$TMP/out"
expect_c bad "fix: $(pad_utf8 68 '\302\247')"

# Every allowed type passes; the rejection message names the rules.
for type in feat fix docs test refactor perf build ci chore revert; do
  expect ok "$type: do one thing"
done
run_hook "oops"
check "rejection message lists the allowed types" grep -q 'feat, fix, docs' "$TMP/out"
run_hook "#42 fix login"
refute "a -m subject starting with # is not reported as empty" grep -q 'empty' "$TMP/out"

# End to end: real commits through the hook with -m, -F and an editor,
# without the machine's own git config (commit.template, commit.status).
GIT_CONFIG_GLOBAL="$TMP/global.gitconfig"
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
: > "$GIT_CONFIG_GLOBAL"
repo="$TMP/e2e"
git init -q -b main "$repo"
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.com
git -C "$repo" config core.autocrlf false
mkdir -p "$TMP/hooks"
cp "$HOOK" "$TMP/hooks/commit-msg"
git -C "$repo" config core.hooksPath "$TMP/hooks"
# The editor prepends $EDIT_TEXT (printf %b escapes) to git's template,
# after running the sed script $EDIT_SED over it, if set.
# SC2016: the editor script expands these itself.
# shellcheck disable=SC2016
printf '%s\n' \
  'sed -e "${EDIT_SED:-}" "$1" > "$1.sed" || exit 1' \
  '{ printf "%b\n" "$EDIT_TEXT"; cat "$1.sed"; } > "$1" && rm -f "$1.sed"' \
  > "$TMP/editor.sh"

# commit_with <-m|-F|editor> <message with escapes> [git commit options...]
commit_with() {
  local how=$1 msg=$2
  shift 2
  echo "$msg" >> "$repo/file" && git -C "$repo" add file || return 2
  case $how in
    -m) git -C "$repo" commit -q "$@" -m "$(printf '%b' "$msg")" ;;
    -F) printf '%b' "$msg" > "$TMP/msgfile" && git -C "$repo" commit -q "$@" -F "$TMP/msgfile" ;;
    editor) EDIT_TEXT=$msg GIT_EDITOR="bash '$TMP/editor.sh'" git -C "$repo" commit -q "$@" ;;
  esac > /dev/null 2>&1
}
saved_subject() { test "$(git -C "$repo" log -1 --format=%s)" = "$1"; }

refute "-m: git keeps a leading # line, so it is the subject" commit_with -m '# anything\nfeat: add login form'
refute "-F: git keeps '#WIP hack' as the subject" commit_with -F '#WIP hack\nfeat: add login form'
refute "-m: '#42 fix login' is not a valid subject" commit_with -m '#42 fix login'
refute "-m: a # line right under the subject is not blank" commit_with -m 'feat: add login form\n#42'
check "-m: a body line starting with # is fine" commit_with -m 'feat: add login form\n\n#42 was the cause'
check "editor: comment lines are dropped" commit_with editor '# a note\nfeat: add the editor flow'
check "editor: git saved the subject without the comment" saved_subject 'feat: add the editor flow'
check "editor -v: the scissors line and diff are dropped" commit_with editor '# a note\nfix: add the verbose flow' -v
check "editor -v: git saved that subject" saved_subject 'fix: add the verbose flow'
git -C "$repo" config core.commentChar ';'
refute "-m with core.commentChar ;: git keeps a ; line" commit_with -m '; a note\nfix: use the comment char'
check "editor with core.commentChar ;: ; lines are dropped" commit_with editor '; a note\nfix: use the comment char'
check "editor with core.commentChar ;: git saved that subject" saved_subject 'fix: use the comment char'
git -C "$repo" config --unset core.commentChar

# A translated git (simulated by rewording its template) or --no-status
# leaves no English template text; the editor still ran, so git strips.
export EDIT_SED='s/^# Please enter.*/# Bitte geben Sie eine Commit-Beschreibung ein./; /^# with /d'
check "editor, translated template: comment lines are dropped" commit_with editor '# Notiz\nfix: add the translated flow'
unset EDIT_SED
check "editor, translated template: git saved that subject" saved_subject 'fix: add the translated flow'
check "editor --no-status: comment lines are dropped" commit_with editor '# a note\nfix: add the no-status flow' --no-status
check "editor --no-status: git saved that subject" saved_subject 'fix: add the no-status flow'
export EDIT_SED='/^chore: replaced below$/d'
check "-e -m: comment lines are dropped" commit_with editor '# a note\nfix: add the edit flow' -e -m 'chore: replaced below'
unset EDIT_SED
check "-e -m: git saved the edited subject" saved_subject 'fix: add the edit flow'
git -C "$repo" config commit.cleanup strip
check "-m with commit.cleanup=strip: git drops a # line" commit_with -m '# a note\nfix: strip by config'
check "-m with commit.cleanup=strip: git saved that subject" saved_subject 'fix: strip by config'
git -C "$repo" config commit.cleanup whitespace
refute "editor with commit.cleanup=whitespace: git keeps a # line" commit_with editor '# a note\nfix: keep by config'
git -C "$repo" config --unset commit.cleanup

# The signal the hook relies on: git exports GIT_EDITOR=: when no editor ran.
cat "$TMP/hooks/commit-msg" > "$TMP/hook.real"
# SC2016: the probe hook expands GIT_EDITOR itself, not this script.
# shellcheck disable=SC2016
printf '#!/bin/sh\nprintf %%s "${GIT_EDITOR-unset}" > "%s"\n' "$TMP/seen" > "$TMP/hooks/commit-msg"
seen() { test "$(cat "$TMP/seen")" "$1" :; }
commit_with -m 'fix: probe'
check "git sets GIT_EDITOR=: for -m" seen =
commit_with -F 'fix: probe'
check "git sets GIT_EDITOR=: for -F" seen =
commit_with editor 'fix: probe'
check "git does not set GIT_EDITOR=: when its editor runs" seen !=
commit_with editor 'fix: probe' -e -m 'fix: probe'
check "git does not set GIT_EDITOR=: for -e" seen !=
cat "$TMP/hook.real" > "$TMP/hooks/commit-msg"

finish
