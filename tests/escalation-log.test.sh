#!/usr/bin/env bash
# Two sessions append to escalation-log.md at once, following the rule:
# pull --rebase --autostash, commit only that file, push, and pull again
# when the push is rejected. Neither entry may be lost, and no conflict
# markers may be committed (the file merges with merge=union).
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

GIT_CONFIG_GLOBAL="$TMP/global.gitconfig"
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
printf '[user]\n\tname = test\n\temail = test@example.com\n[core]\n\tautocrlf = false\n' \
  > "$GIT_CONFIG_GLOBAL"

q() { "$@" > /dev/null 2>&1; }
log=escalation-log.md

git init -q --bare -b main "$TMP/origin.git"
q git clone "$TMP/origin.git" "$TMP/seed"
cp "$ROOT/.gitattributes" "$TMP/seed/.gitattributes"
printf '# Escalation log\n\n## Entries\n' > "$TMP/seed/$log"
q git -C "$TMP/seed" add -A
q git -C "$TMP/seed" commit -m "docs: start the log"
q git -C "$TMP/seed" push origin main
q git clone "$TMP/origin.git" "$TMP/a"
q git clone "$TMP/origin.git" "$TMP/b"

append() { printf '\n### %s\n\n- Task: %s\n' "$2" "$2" >> "$1/$log"; }
# push_retry <clone>: push; when rejected, pull again and push
push_retry() {
  git -C "$1" push -q origin main ||
    { git -C "$1" pull -q --rebase && git -C "$1" push -q origin main; }
} > /dev/null 2>&1
# log_entry <clone> <name>: the rule's steps, after the entry is written
log_entry() {
  git -C "$1" pull -q --rebase --autostash &&
    git -C "$1" commit -q -m "docs(escalation): $2" -- "$log" &&
    push_retry "$1"
} > /dev/null 2>&1
clean_and_complete() { # clean_and_complete <entry names...>
  local name
  q git -C "$TMP/check" pull -q
  ! grep -qE '^(<<<<<<<|=======|>>>>>>>)' "$TMP/check/$log" || return 1
  for name in "$@"; do grep -qx "### $name" "$TMP/check/$log" || return 1; done
}
q git clone "$TMP/origin.git" "$TMP/check"

# 1. B writes its entry; A pushes one meanwhile; B's autostash meets it.
append "$TMP/b" "entry B1"
append "$TMP/a" "entry A1"
check "A logs its entry" log_entry "$TMP/a" "A1"
check "B logs its entry over A's (autostash)" log_entry "$TMP/b" "B1"
check "both entries kept, no conflict markers" clean_and_complete "entry A1" "entry B1"

# 2. Both commit; B's push is rejected, so B pulls again and pushes.
q git -C "$TMP/a" pull -q
q git -C "$TMP/b" pull -q
append "$TMP/a" "entry A2"
append "$TMP/b" "entry B2"
q git -C "$TMP/a" commit -q -m "docs(escalation): A2" -- "$log"
q git -C "$TMP/b" commit -q -m "docs(escalation): B2" -- "$log"
check "A pushes first" q git -C "$TMP/a" push -q origin main
check "B's rejected push is retried after a pull" push_retry "$TMP/b"
check "all entries kept, no conflict markers" \
  clean_and_complete "entry A1" "entry B1" "entry A2" "entry B2"

# 3. A records the outcome of its entry while B adds a new entry. The
# outcome is appended as a line of its own, never edited into the entry,
# so the union merge cannot keep a stale copy next to the new one.
q git -C "$TMP/a" pull -q
q git -C "$TMP/b" pull -q
printf -- '\n- Outcome (entry A1): needed\n' >> "$TMP/a/$log"
append "$TMP/b" "entry B3"
check "A logs the outcome" log_entry "$TMP/a" "outcome of A1"
check "B logs its entry over the outcome" log_entry "$TMP/b" "B3"
check "the outcome and the new entry are both kept" \
  clean_and_complete "entry A1" "entry B1" "entry A2" "entry B2" "entry B3"
one_outcome() { [ "$(grep -c '^- Outcome (entry A1): needed$' "$TMP/check/$log")" -eq 1 ]; }
check "the outcome appears once" one_outcome

# The log's own format asks for outcomes as appended lines, not edits.
format_block() { sed -n '/^## Entry format/,/^## Entries/p' "$ROOT/$log"; }
appends_outcomes() {
  format_block | grep -q '^- Outcome (YYYY-MM-DD: <entry title>): ' &&
    ! format_block | grep -q '^- Outcome: '
}
check "the format appends outcomes instead of editing entries" appends_outcomes

finish
