#!/usr/bin/env bash
# Tests for scripts/check-drift.sh and scripts/copy-template.sh (D153,
# D154): a throwaway ai-workflow clone made from this repository's
# hooks, scripts and templates, with upgrade notes of its own; throwaway
# projects set up from it; and what the check reports after each kind of
# change upstream or in the project. The end checks docs/upgrading.md.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

# Keep the machine's own git config, excludes and any outer hook's GIT_*
# variables out of the tests.
clear_git_env
GIT_CONFIG_GLOBAL="$TMP/global.gitconfig"
GIT_CONFIG_NOSYSTEM=1
XDG_CONFIG_HOME="$TMP/xdg"
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM XDG_CONFIG_HOME
printf '[user]\n\tname = test\n\temail = test@example.com\n[core]\n\tautocrlf = false\n' \
  > "$GIT_CONFIG_GLOBAL"

q() { "$@" > /dev/null 2>&1; }

# --- the clone: this repository's hooks, scripts and templates, with
# upgrade notes of its own (the slow git below knows its name)
CLONE="$TMP/aiwf-clone"
mkdir -p "$CLONE/docs"
cp -R "$ROOT/hooks" "$ROOT/scripts" "$ROOT/templates" "$CLONE/"
cp "$ROOT/.gitattributes" "$CLONE/"
printf '# Upgrade notes\n' > "$CLONE/docs/upgrading.md"
# note <clone> <date> <title>: appends an upgrade note to that clone
note() {
  printf '\n## %s: %s\n\n- From: a test.\n- Do: %s.\n- Done when: never.\n' "$2" "$3" "$3" \
    >> "$1/docs/upgrading.md"
}
note "$CLONE" 2026-11-10 'Set the first test variable'
git init -q -b main "$CLONE"
# upstream <message>: commits every change in the clone
upstream() { git -C "$CLONE" add -A && git -C "$CLONE" commit -q -m "$1"; }
upstream "chore: start the clone"
clone_head() { git -C "$CLONE" rev-parse HEAD; }
# Its main tracks a remote's main, the remote's default branch: a clone
# with no upstream, or on another branch, is drift of its own.
git clone -q --bare "$CLONE" "$TMP/aiwf-origin.git"
git -C "$CLONE" remote add origin "$TMP/aiwf-origin.git"
git -C "$CLONE" fetch -q origin
git -C "$CLONE" branch -q -u origin/main
git -C "$CLONE" remote set-head origin main

DRIFT="$CLONE/scripts/check-drift.sh"
COPY="$CLONE/scripts/copy-template.sh"
INSTALL="$CLONE/hooks/install.sh"

# new_project <dir>: a git repository whose AGENTS.md names the rules
new_project() {
  git init -q -b main "$1"
  printf 'This project follows https://github.com/Tonttu84/ai-workflow.\n' > "$1/AGENTS.md"
}
commit_all() { git -C "$1" add -A && git -C "$1" commit -q --no-verify -m "$2"; }

# drift [args]: the check, its output kept in $TMP/out; its status
drift() { bash "$DRIFT" "$@" > "$TMP/out" 2>&1; }
status_is() { # status_is <status> [args]
  local want=$1
  shift
  drift "$@"
  [ "$?" -eq "$want" ]
}
says() { grep -qF -- "$1" "$TMP/out"; }
silent() { test ! -s "$TMP/out"; }
# session <json> [check-drift.sh]: --session with that input; its status
session() { printf '%s' "$1" | bash "${2:-$DRIFT}" --session > "$TMP/out" 2>&1; }
json_for() { # json_for <dir>: the SessionStart input Claude Code sends
  printf '{"session_id":"t1","transcript_path":"/t.jsonl","cwd":"%s","hook_event_name":"SessionStart","source":"startup"}' "$1"
}

check "--help prints the comment block and no code" help_ok "$DRIFT"
check "the helper's --help prints the comment block and no code" help_ok "$COPY"

# --- 1. a fresh install records itself, and the check finds no drift
P="$TMP/fresh"
new_project "$P"
RECORD="$P/.ai-workflow-copies"
check "a fresh install succeeds" q bash "$INSTALL" "$P"
check "it writes the record" test -f "$RECORD"
check "the record lists each hook with the clone's commit" \
  grep -qxF "$(clone_head) hooks/pre-push .githooks/pre-push" "$RECORD"
check "check-walkthrough too" grep -qxF "$(clone_head) hooks/check-walkthrough .githooks/check-walkthrough" "$RECORD"
refute "an install never records the upgrade notes as followed" grep -q '^notes ' "$RECORD"
check "the record is staged" q git -C "$P" ls-files --error-unmatch .ai-workflow-copies
refute "the record names no path outside the project" grep -qF "$TMP" "$RECORD"
check "the helper copies gate.conf" q bash "$COPY" templates/gate.conf gate.conf "$P"
check "the copy is the template" cmp -s "$CLONE/templates/gate.conf" "$P/gate.conf"
check "and is recorded" grep -qxF "$(clone_head) templates/gate.conf gate.conf" "$RECORD"
check "the helper stages the copy" q git -C "$P" ls-files --error-unmatch gate.conf
commit_all "$P" "chore: set up the project"
check "until the notes are recorded as followed, they are drift" status_is 1 "$P"
check "listed as unknown" says 'unknown'
check "the helper records the notes as followed" q bash "$COPY" --notes-followed "$P"
check "with the clone's commit" grep -qxF "notes $(clone_head)" "$RECORD"
commit_all "$P" "chore: record the upgrade notes as followed"
check "1. a fresh install: no drift, exit 0" status_is 0 "$P"
check "it says so" says 'No drift'
check "from a subdirectory too" status_is 0 "$P/.githooks"
session "$(json_for "$P")"
check "--session with no drift exits 0" test "$?" -eq 0
check "--session with no drift prints nothing" silent

# --- 2. a hook changed upstream after the install
printf '# an upstream change\n' >> "$CLONE/hooks/check-commits"
upstream "fix: change a hook upstream"
check "2. a hook changed upstream is drift, exit 1" status_is 1 "$P"
check "it names the copy" says '.githooks/check-commits'
check "it names the reinstall command" says 'hooks/install.sh'
refute "it does not report the unchanged hooks" says '.githooks/commit-msg'
session "$(json_for "$P")"
check "--session with drift exits 0" test "$?" -eq 0
check "--session names the copy" says '.githooks/check-commits'
check "--session names the reinstall command" says 'hooks/install.sh'
check "--session points to the full report" says 'scripts/check-drift.sh'
check "the reinstall succeeds" q bash "$INSTALL" "$P"
commit_all "$P" "chore: update the hooks"
check "after the reinstall: no drift" status_is 0 "$P"
check "the reinstall records the new commit" \
  grep -qxF "$(clone_head) hooks/check-commits .githooks/check-commits" "$RECORD"
# A gate script copied with --gate is an exact copy too.
check "an install with --gate succeeds" q bash "$INSTALL" --gate "$P"
commit_all "$P" "chore: add the gate scripts"
check "the gate scripts are recorded" \
  grep -qxF "$(clone_head) scripts/check-features.sh .ai-workflow/check-features.sh" "$RECORD"
check "with them: no drift" status_is 0 "$P"
printf '# an upstream change\n' >> "$CLONE/scripts/check-red-green.sh"
upstream "fix: change a gate script upstream"
check "a gate script changed upstream is drift" status_is 1 "$P"
check "it names the copy" says '.ai-workflow/check-red-green.sh'
check "and the reinstall command with --gate" says 'install.sh --gate'
q bash "$INSTALL" --gate "$P"
commit_all "$P" "chore: update the gate scripts"
check "after that reinstall: no drift" status_is 0 "$P"

# --- 3 and 4. a template copied with the helper and edited locally:
# only an upstream change is drift, and only it is shown
WF=.github/workflows/commit-check.yml
check "the helper copies commit-check.yml" q bash "$COPY" templates/commit-check.yml "$WF" "$P"
check "it makes the folders" test -f "$P/$WF"
{ printf '# LOCAL-EDIT\n'; cat "$P/$WF"; } > "$TMP/edited" && cp "$TMP/edited" "$P/$WF"
commit_all "$P" "ci: edit the commit check"
check "4. a local edit with no upstream change is not drift" status_is 0 "$P"
printf '# FIRST-UPSTREAM\n' >> "$CLONE/templates/commit-check.yml"
upstream "feat: change a template upstream"
first=$(clone_head)
check "3. a template changed upstream is drift" status_is 1 "$P"
check "it names the copy" says "$WF"
check "and the template" says 'templates/commit-check.yml'
check "it says the commit came from the record" says 'recorded'
check "it shows the upstream change" says '+# FIRST-UPSTREAM'
refute "and not the local edit" says 'LOCAL-EDIT'
check "it names the helper that merges it" says 'scripts/copy-template.sh'
session "$(json_for "$P")"
check "--session names the copy" says "$WF"
refute "--session leaves the diff to the full report" says '+# FIRST-UPSTREAM'
# The helper merges the upstream change into the edited copy.
check "the helper merges the upstream change" q bash "$COPY" templates/commit-check.yml "$WF" "$P"
check "the copy keeps the local edit" grep -qxF '# LOCAL-EDIT' "$P/$WF"
check "and has the upstream change" grep -qxF '# FIRST-UPSTREAM' "$P/$WF"
check "the record moves to the clone's commit" grep -qxF "$first templates/commit-check.yml $WF" "$RECORD"
commit_all "$P" "ci: take the upstream change to the commit check"
check "after the merge: no drift" status_is 0 "$P"
# A merge that conflicts leaves the markers and the record as it was.
sed 's/^# FIRST-UPSTREAM$/# LOCAL-CLASH/' "$P/$WF" > "$TMP/edited" && cp "$TMP/edited" "$P/$WF"
commit_all "$P" "ci: edit the line upstream changes next"
sed 's/^# FIRST-UPSTREAM$/# UPSTREAM-CLASH/' "$CLONE/templates/commit-check.yml" > "$TMP/edited" &&
  cp "$TMP/edited" "$CLONE/templates/commit-check.yml"
upstream "feat: change the same line upstream"
cp "$RECORD" "$TMP/record.before"
refute "a conflicting merge fails" q bash "$COPY" templates/commit-check.yml "$WF" "$P"
check "it leaves the conflict markers" grep -q '^<<<<<<<' "$P/$WF"
check "and the record as it was" cmp -s "$TMP/record.before" "$RECORD"
# Resolved by hand, the copy is recorded at the clone's commit.
{ printf '# LOCAL-EDIT\n'; cat "$CLONE/templates/commit-check.yml"; } > "$P/$WF"
check "--record records a copy brought up to date by hand" \
  q bash "$COPY" --record "$P" templates/commit-check.yml "$WF"
check "at the clone's commit" grep -qxF "$(clone_head) templates/commit-check.yml $WF" "$RECORD"
commit_all "$P" "ci: resolve the commit check by hand"
check "after that: no drift" status_is 0 "$P"
# The helper refuses a template the clone has not committed, a copy it
# cannot merge without a base, and a path outside the project.
printf 'x\n' >> "$CLONE/templates/dependabot.yml"
refute "the helper refuses a template with uncommitted changes in the clone" \
  q bash "$COPY" templates/dependabot.yml .github/dependabot.yml "$P"
check "and copies nothing" test ! -e "$P/.github/dependabot.yml"
git -C "$CLONE" checkout -q -- templates/dependabot.yml
printf 'version: 2\n' > "$P/.github/dependabot.yml"
refute "an unrecorded copy that differs is refused" \
  q bash "$COPY" templates/dependabot.yml .github/dependabot.yml "$P"
check "it is left as it was" grep -qx 'version: 2' "$P/.github/dependabot.yml"
check "--force replaces it" q bash "$COPY" --force templates/dependabot.yml .github/dependabot.yml "$P"
check "with the template" cmp -s "$CLONE/templates/dependabot.yml" "$P/.github/dependabot.yml"
refute "a path outside the project is refused" q bash "$COPY" templates/gate.conf ../outside.conf "$P"
check "and nothing is written there" test ! -e "$TMP/outside.conf"
refute "an absolute path is refused" q bash "$COPY" templates/gate.conf "$TMP/abs.conf" "$P"
check "and nothing is written there either" test ! -e "$TMP/abs.conf"
refute "a file outside templates/ is refused" q bash "$COPY" hooks/commit-msg x "$P"
refute "a missing template is refused" q bash "$COPY" templates/no-such.yml x "$P"
refute "--record of a file that is not there is refused" q bash "$COPY" --record "$P" templates/gate.conf missing.conf
commit_all "$P" "ci: add dependabot"

# A copy checked out with CRLF endings (core.autocrlf=true, as Git for
# Windows sets it) merges an upstream change as cleanly as an LF one and
# keeps its endings; without that every line conflicts.
CR="$TMP/crlf"
FC=.github/workflows/feature-check.yml
new_project "$CR"
q bash "$INSTALL" "$CR"
q bash "$COPY" --notes-followed "$CR"
q bash "$COPY" templates/feature-check.yml "$FC" "$CR"
q bash "$COPY" templates/gate.conf gate.conf "$CR"
commit_all "$CR" "ci: add the feature check"
git -C "$CR" config core.autocrlf true
rm "$CR/$FC" && git -C "$CR" checkout -q -- "$FC"
# all_crlf <file>: every line ends in CR LF (counted, since Windows grep
# may drop CRs)
all_crlf() { test "$(tr -d '\r' < "$1" | wc -c)" -eq "$(($(wc -c < "$1") - $(wc -l < "$1")))"; }
refute "all_crlf: an LF file is not" all_crlf "$CLONE/templates/feature-check.yml"
check "the checkout has CRLF endings" all_crlf "$CR/$FC"
{ printf '# CRLF-LOCAL\r\n'; cat "$CR/$FC"; } > "$TMP/edited" && cp "$TMP/edited" "$CR/$FC"
commit_all "$CR" "ci: edit the feature check"
printf '# CRLF-UPSTREAM\n' >> "$CLONE/templates/feature-check.yml"
upstream "feat: change the feature-check template"
check "a CRLF copy merges an upstream change cleanly" q bash "$COPY" templates/feature-check.yml "$FC" "$CR"
refute "with no conflict markers" grep -q '^<<<<<<<' "$CR/$FC"
check "it keeps the local edit" grep -q '^# CRLF-LOCAL' "$CR/$FC"
check "and takes the change" grep -q '^# CRLF-UPSTREAM' "$CR/$FC"
check "with CRLF endings throughout" all_crlf "$CR/$FC"
commit_all "$CR" "ci: take the upstream change"
check "and the check finds no drift then" status_is 0 "$CR"
# A CRLF checkout of the template as it is counts as the same copy.
G2="$TMP/crlf-same"
new_project "$G2"
q bash "$INSTALL" "$G2"
mkdir -p "$G2/.github/workflows"
awk '{ print $0 "\r" }' "$CLONE/templates/feature-check.yml" > "$G2/$FC"
check "an unrecorded CRLF copy of the template as it is gets recorded" \
  q bash "$COPY" templates/feature-check.yml "$FC" "$G2"
check "unchanged" all_crlf "$G2/$FC"

# --- 5. a project migrated before the record existed: the check guesses
# the closest upstream version of each template, and says so
O="$TMP/old"
new_project "$O"
mkdir -p "$O/.githooks" "$O/.github/workflows"
for f in commit-msg pre-push check-commits check-walkthrough; do cp "$CLONE/hooks/$f" "$O/.githooks/$f"; done
git -C "$O" config core.hooksPath .githooks
{ printf '# OLD-LOCAL-EDIT\n'; git -C "$CLONE" show "$first:templates/commit-check.yml"; } > "$O/$WF"
cp "$CLONE/templates/gate.conf" "$O/gate.conf"
commit_all "$O" "chore: migrate before the record"
printf '# SECOND-UPSTREAM\n' >> "$CLONE/templates/commit-check.yml"
upstream "feat: change the template again"
check "5. no record: an upstream change is drift" status_is 1 "$O"
check "it says the commit was guessed" says 'guessed'
check "it names the closest version's commit" says "${first:0:7}"
check "it shows the change since that version" says '+# SECOND-UPSTREAM'
refute "not the change before it, which the copy has" says '+# FIRST-UPSTREAM'
refute "nor the local edit" says 'OLD-LOCAL-EDIT'
refute "a template copied unchanged at the clone's commit is not drift" says 'templates/gate.conf'
check "the helper merges from the guessed commit with --base" \
  q bash "$COPY" --base "$first" templates/commit-check.yml "$WF" "$O"
check "keeping the local edit" grep -qxF '# OLD-LOCAL-EDIT' "$O/$WF"
check "and taking the change" grep -qxF '# SECOND-UPSTREAM' "$O/$WF"
git -C "$O" reset -q --hard
# The recorded project takes the same change with a plain merge.
check "a recorded copy merges it with no --base" q bash "$COPY" templates/commit-check.yml "$WF" "$P"
commit_all "$P" "ci: take the second upstream change"
check "and has no drift then" status_is 0 "$P"

# --- 6. required files: a committed gate.conf, and the D151 ignores
# where .claude/ exists
G="$TMP/gate"
new_project "$G"
q bash "$INSTALL" "$G"
q bash "$COPY" --notes-followed "$G"
commit_all "$G" "chore: install the hooks"
check "6. a missing gate.conf is drift" status_is 1 "$G"
check "it says gate.conf is missing" says 'gate.conf is missing'
q bash "$COPY" templates/gate.conf gate.conf "$G"
git -C "$G" rm -q --cached gate.conf
check "an uncommitted gate.conf is drift" status_is 1 "$G"
check "it says gate.conf is not committed" says 'gate.conf is not committed'
commit_all "$G" "chore: add the gate"
check "a committed gate.conf is not" status_is 0 "$G"
mkdir -p "$G/.claude"
check "a .claude/ folder without the D151 ignores is drift" status_is 1 "$G"
check "it names .claude/worktrees/" says '.claude/worktrees/'
check "it names .claude/settings.local.json" says '.claude/settings.local.json'
printf '.claude/worktrees/\n.claude/settings.local.json\n' > "$G/.git/info/exclude"
check "rules in .git/info/exclude do not count" status_is 1 "$G"
mkdir -p "$XDG_CONFIG_HOME/git"
printf '.claude/\n' > "$XDG_CONFIG_HOME/git/ignore"
check "nor in a global excludes file" status_is 1 "$G"
rm -f "$XDG_CONFIG_HOME/git/ignore" "$G/.git/info/exclude"
printf '.claude/worktrees/\n.claude/settings.local.json\n' > "$G/.gitignore"
check "an uncommitted .gitignore does not count" status_is 1 "$G"
commit_all "$G" "chore: ignore Claude Code's local files"
check "a committed .gitignore does" status_is 0 "$G"
printf '.claude/*\n!.claude/settings.json\n' > "$G/.gitignore"
commit_all "$G" "chore: ignore .claude/ but its shared settings"
check "a wider rule counts too" status_is 0 "$G"
printf '.claude/worktrees/\n' > "$G/.gitignore"
commit_all "$G" "chore: ignore only the worktrees"
check "one rule missing is drift" status_is 1 "$G"
refute "and only that one is named" says '.claude/worktrees/'
# A negated rule takes the file back out of the ignores.
printf '.claude/*\n!.claude/settings.local.json\n' > "$G/.gitignore"
commit_all "$G" "chore: un-ignore the local settings"
check "a negated rule for a file is drift" status_is 1 "$G"
check "it names that file" says '.claude/settings.local.json'
refute "and not the other" says '.claude/worktrees/'
# A tracked .gitignore with the rules only in the working tree.
printf '*.log\n' > "$G/.gitignore"
commit_all "$G" "chore: ignore logs only"
printf '*.log\n.claude/worktrees/\n.claude/settings.local.json\n' > "$G/.gitignore"
check "rules only in a tracked .gitignore's uncommitted change do not count" status_is 1 "$G"
check "it names both paths" says '.claude/worktrees/'
commit_all "$G" "chore: ignore Claude Code's local files again"
check "committed, they do" status_is 0 "$G"
rm -rf "$G/.claude"
check "without .claude/ the ignores are not needed" status_is 0 "$G"

# --- 7. upgrade notes: those added after the record's notes commit
note "$CLONE" 2026-11-19 'Set the second test variable'
upstream "docs: add an upgrade note"
check "7. a note added after the recorded commit is drift" status_is 1 "$P"
check "it is listed" says 'Set the second test variable'
refute "one from before it is not" says 'Set the first test variable'
check "the helper records the notes as followed" q bash "$COPY" --notes-followed "$P"
check "with the clone's commit" grep -qxF "notes $(clone_head)" "$RECORD"
commit_all "$P" "chore: follow the upgrade notes"
check "then the note is not listed" status_is 0 "$P"
check "no record: every note is listed" status_is 1 "$O"
check "the first" says 'Set the first test variable'
check "and the second" says 'Set the second test variable'
check "flagged as unknown" says 'unknown'
# A reinstall over our older hooks writes a record, but leaves the notes
# unknown: only --notes-followed says they were followed.
check "an install over hooks of ours from before the record succeeds" q bash "$INSTALL" "$O"
check "it writes a record" test -f "$O/.ai-workflow-copies"
refute "with no notes line" grep -q '^notes ' "$O/.ai-workflow-copies"
drift "$O"
check "the notes are still listed after it" says 'Set the first test variable'
check "still as unknown" says 'unknown'
git -C "$O" reset -q --hard
git -C "$O" clean -q -fd
# A project migrated with --git-hooks commits no hooks, so the install on
# a new clone finds none of ours; it still records no notes as followed.
GH="$TMP/githooks"
new_project "$GH"
q bash "$INSTALL" --git-hooks "$GH"
q bash "$COPY" templates/gate.conf gate.conf "$GH"
commit_all "$GH" "chore: migrate with the hooks in .git/hooks"
git clone -q "$GH" "$TMP/githooks-clone"
check "a --git-hooks install on a new clone succeeds" q bash "$INSTALL" --git-hooks "$TMP/githooks-clone"
refute "and records no notes as followed" grep -q '^notes ' "$TMP/githooks-clone/.ai-workflow-copies"
drift "$TMP/githooks-clone"
check "so the notes are still listed" says 'Set the first test variable'

# --- a clone older than the record: the check says so, and the helper
# neither merges nor records backwards
OLDC="$TMP/aiwf-older"
git clone -q "$CLONE" "$OLDC"
git -C "$OLDC" reset -q --hard HEAD~2
bash "$OLDC/scripts/check-drift.sh" "$P" > "$TMP/out" 2>&1
check "a clone older than the record is drift" test "$?" -eq 1
check "it says the clone is older than the record" says 'older than the record'
cp "$RECORD" "$TMP/record.before"
cp "$P/$WF" "$TMP/wf.before"
refute "the helper refuses to merge from a clone older than the record" \
  q bash "$OLDC/scripts/copy-template.sh" templates/commit-check.yml "$WF" "$P"
check "the copy is as it was" cmp -s "$TMP/wf.before" "$P/$WF"
refute "it refuses to record a copy backwards" \
  q bash "$OLDC/scripts/copy-template.sh" --record "$P" templates/commit-check.yml "$WF"
refute "or the notes" q bash "$OLDC/scripts/copy-template.sh" --notes-followed "$P"
check "the record is as it was" cmp -s "$TMP/record.before" "$RECORD"

# --- 8. --session: the hook's JSON on stdin, silence where there is
# nothing to say, always exit 0, a short report, an internal deadline
session "$(json_for "$O")"
check "8. --session reads the cwd from the JSON" says 'Set the first test variable'
check "--session points to the full report" says 'scripts/check-drift.sh'
session "$(json_for "$O/.githooks")"
check "--session from a subdirectory" says 'Set the first test variable'
mkdir -p "$TMP/plain"
session "$(json_for "$TMP/plain")"
check "--session outside a git repository exits 0" test "$?" -eq 0
check "--session outside a git repository prints nothing" silent
git init -q -b main "$TMP/other"
session "$(json_for "$TMP/other")"
check "--session in a repository that is not migrated exits 0" test "$?" -eq 0
check "--session in a repository that is not migrated prints nothing" silent
printf 'Some other project.\n' > "$TMP/other/AGENTS.md"
session "$(json_for "$TMP/other")"
check "nor with an AGENTS.md that does not name the rules" silent
session "$(json_for "$TMP/no-such-dir")"
check "--session for a missing directory exits 0" test "$?" -eq 0
check "--session for a missing directory prints nothing" silent
for bad in '' 'not json' '{"source":"startup"}' '{"cwd":42}'; do
  session "$bad"
  check "--session with input '$bad' exits 0" test "$?" -eq 0
  check "--session with input '$bad' prints nothing" silent
done
check "--session with no input exits 0" q bash "$DRIFT" --session < /dev/null
check "--session with a directory argument exits 0" q bash "$DRIFT" --session "$P" < /dev/null
# JSON escapes: a path with a space and an a-umlaut, its slashes escaped
S="$TMP/my proj ä"
new_project "$S"
q bash "$INSTALL" "$S"
commit_all "$S" "chore: install the hooks"
escaped=$(printf '%s' "$S" | sed 's|/|\\/|g')
session "{\"cwd\": \"$escaped\", \"source\": \"resume\"}"
check "--session reads an escaped path with a space and ä" says 'gate.conf is missing'
if command -v cygpath > /dev/null 2>&1; then # Windows: Claude Code sends D:\\... paths
  windows=$(cygpath -w "$S" | sed 's|\\|\\\\|g')
  session "{\"cwd\":\"$windows\"}"
  check "--session reads a Windows path" says 'gate.conf is missing'
fi
# A long report is cut, with the pointer kept.
MANY="$TMP/many"
git clone -q "$CLONE" "$MANY"
for i in $(seq 1 80); do
  note "$MANY" 2026-11-19 "A long upgrade note title, number $i, that goes on and on to fill the session report"
done
git -C "$MANY" add -A && git -C "$MANY" commit -q -m "docs: add many notes"
session "$(json_for "$O")" "$MANY/scripts/check-drift.sh"
check "--session with many notes exits 0" test "$?" -eq 0
check "--session output stays under 3,000 characters" test "$(wc -c < "$TMP/out")" -lt 3000
check "it says it was cut" says 'cut'
check "and keeps the pointer to the full report" says 'check-drift.sh'
bash "$MANY/scripts/check-drift.sh" "$O" > "$TMP/out" 2>&1
check "the full report is not cut" says 'number 80,'
# The deadline: a git that hangs on the clone stops the check in time.
mkdir -p "$TMP/slowbin"
# SC2016: the fake git expands "$*" and "$@" itself.
# shellcheck disable=SC2016
printf '#!/usr/bin/env bash\ncase "$*" in *aiwf-clone*) sleep 30 ;; esac\nexec "%s" "$@"\n' \
  "$(command -v git)" > "$TMP/slowbin/git"
chmod +x "$TMP/slowbin/git"
start=$SECONDS
json_for "$P" | PATH="$TMP/slowbin:$PATH" CHECK_DRIFT_DEADLINE=2 bash "$DRIFT" --session > "$TMP/out" 2>&1
code=$?
took=$((SECONDS - start))
check "--session past its deadline exits 0" test "$code" -eq 0
check "--session stops at its deadline (took ${took}s for 2)" test "$took" -le 9
check "it says it stopped at its deadline" says 'deadline'
check "and points to the full report" says 'check-drift.sh'

# --- 9. the clone behind its remote-tracking branch, from local refs
BEHIND="$TMP/lagging" # no "behind" in the path the report names
git clone -q "$CLONE" "$BEHIND"
printf 'more\n' > "$CLONE/extra.txt"
upstream "docs: add a file upstream"
git -C "$BEHIND" fetch -q
drift_behind() { bash "$BEHIND/scripts/check-drift.sh" "$@" > "$TMP/out" 2>&1; }
drift_behind "$P"
check "9. a clone behind its remote-tracking branch is drift" test "$?" -eq 1
check "it says the clone is behind" says 'behind'
check "it names the branch" says 'origin/main'
session "$(json_for "$P")" "$BEHIND/scripts/check-drift.sh"
check "--session says so too" says 'behind'
git -C "$BEHIND" merge -q --ff-only
drift_behind "$P"
check "once pulled: no drift" test "$?" -eq 0
refute "and nothing about being behind" says 'behind'

# --- the record is data: a line that is not a full SHA and two plain
# relative paths (or "notes" and a full SHA) is reported as not valid,
# never handed to git and never echoed (cold review, finding 1)
J="$TMP/inject"
new_project "$J"
q bash "$INSTALL" "$J"
q bash "$COPY" templates/gate.conf gate.conf "$J"
q bash "$COPY" --notes-followed "$J"
commit_all "$J" "chore: set up the project"
cp "$J/.ai-workflow-copies" "$TMP/record.ok"
VICTIM="$TMP/victim.txt"
printf 'keep me\n' > "$VICTIM"
intact() { grep -qx 'keep me' "$VICTIM"; }
sha=$(clone_head)
for line in "--output=$VICTIM templates/gate.conf gate.conf" "notes --output=$VICTIM" \
  "abc1234 templates/gate.conf gate.conf" "$sha templates/../hooks/pre-push gate.conf" \
  "$sha templates/gate.conf ../outside.conf" "$sha templates/gate.conf -gate.conf" \
  "$sha templates/gate.conf /abs/gate.conf" "$sha templates/gate.conf my gate.conf" \
  "$sha templates/gate.conf gate$(printf '\033')[31m.conf"; do
  { cat "$TMP/record.ok"; printf '%s\n' "$line"; } > "$J/.ai-workflow-copies"
  shown=$(printf '%s' "$line" | tr -d '\033' | cut -c 1-30)
  check "the record line '$shown' is drift" status_is 1 "$J"
  check "it is reported as not valid ('$shown')" says 'is not valid'
  check "the victim is intact ('$shown')" intact
  refute "the line is not echoed ('$shown')" grep -qE -e "$(printf '\033')|--output=" "$TMP/out"
  session "$(json_for "$J")"
  check "--session exits 0 ('$shown')" test "$?" -eq 0
  check "--session reports it ('$shown')" says 'is not valid'
  check "the victim is intact after --session ('$shown')" intact
done
cp "$TMP/record.ok" "$J/.ai-workflow-copies"
check "with the record restored: no drift" status_is 0 "$J"
bash "$COPY" --base abc1234 templates/gate.conf gate.conf "$J" > /dev/null 2>&1
check "the helper's --base must be a full SHA: exit 2" test "$?" -eq 2
bash "$COPY" --base "--output=$VICTIM" templates/gate.conf gate.conf "$J" > /dev/null 2>&1
check "an option as --base: exit 2" test "$?" -eq 2
check "the victim is intact after the helper" intact
refute "the helper refuses a path with a space" q bash "$COPY" templates/gate.conf "my gate.conf" "$J"
printf 'abc1234 templates/gate.conf gate.conf\n' >> "$J/.ai-workflow-copies"
cp "$J/.ai-workflow-copies" "$TMP/record.bad"
refute "the helper will not rewrite a record with a line that is not valid" \
  q bash "$COPY" --notes-followed "$J"
check "and leaves it as it was" cmp -s "$TMP/record.bad" "$J/.ai-workflow-copies"
cp "$TMP/record.ok" "$J/.ai-workflow-copies"

# --- a git call that fails is a line of the report and counts as
# drift, never silence (cold review, finding 2)
F="$TMP/failing"
new_project "$F"
q bash "$INSTALL" "$F"
q bash "$COPY" templates/gate.conf gate.conf "$F"
mkdir -p "$F/.claude" "$F/.github/workflows"
printf '.claude/worktrees/\n.claude/settings.local.json\n' > "$F/.gitignore"
cp "$CLONE/templates/commit-check.yml" "$F/$WF" # not recorded: compared by a guess
commit_all "$F" "chore: set up the project"
mkdir -p "$TMP/failbin"
# The fake git fails the subcommand $FAIL_GIT names, and runs the rest.
# SC2016: the fake git expands its own variables.
# shellcheck disable=SC2016
printf '%s\n' '#!/usr/bin/env bash' 'skip=0 sub=' \
  'for a in "$@"; do' \
  '  if [ "$skip" = 1 ]; then skip=0; continue; fi' \
  '  case $a in -C | -c) skip=1 ;; -*) ;; *) sub=$a; break ;; esac' \
  'done' \
  'if [ "$sub" = "$FAIL_GIT" ]; then echo "fatal: $sub failed on purpose" >&2; exit 128; fi' \
  "exec \"$(command -v git)\" \"\$@\"" > "$TMP/failbin/git"
chmod +x "$TMP/failbin/git"
# failing <subcommand> <project>: the check with that git subcommand failing
failing() { FAIL_GIT=$1 PATH="$TMP/failbin:$PATH" bash "$DRIFT" "$2" > "$TMP/out" 2>&1; }
for sub in hash-object check-ignore log cat-file show diff ls-files ls-tree status rev-list config \
  symbolic-ref; do
  failing "$sub" "$F"
  check "a failing git $sub is drift" test "$?" -eq 1
  check "it says git $sub failed" says "git $sub failed"
done
failing blame "$P"
check "a failing git blame is drift" test "$?" -eq 1
check "it says git blame failed" says 'git blame failed'
json_for "$F" | FAIL_GIT=check-ignore PATH="$TMP/failbin:$PATH" bash "$DRIFT" --session > "$TMP/out" 2>&1
check "--session with a failing git exits 0" test "$?" -eq 0
check "and says what failed" says 'git check-ignore failed'

# --- hooks in .git/hooks (--git-hooks) and under husky (--copy-only)
# are compared too, byte for byte (cold review, finding 6)
H="$TMP/gh-project"
new_project "$H"
q bash "$INSTALL" --git-hooks "$H"
q bash "$COPY" templates/gate.conf gate.conf "$H"
q bash "$COPY" --notes-followed "$H"
commit_all "$H" "chore: set up the project"
check "a --git-hooks project: no drift" status_is 0 "$H"
K="$TMP/husky-project"
new_project "$K"
git -C "$K" config core.hooksPath .husky/_
q bash "$INSTALL" --copy-only "$K"
q bash "$COPY" templates/gate.conf gate.conf "$K"
q bash "$COPY" --notes-followed "$K"
commit_all "$K" "chore: set up the project"
check "a --copy-only project: no drift" status_is 0 "$K"
printf '# another upstream change\n' >> "$CLONE/hooks/check-commits"
upstream "fix: change a hook upstream again"
check "--git-hooks: a hook changed upstream is drift" status_is 1 "$H"
check "it names the copy in .git/hooks" says '.git/hooks/check-commits differs'
check "and the --git-hooks reinstall" says 'install.sh --git-hooks'
check "--copy-only: a hook changed upstream is drift" status_is 1 "$K"
check "it names the copy in .githooks" says '.githooks/check-commits differs'
check "and the --copy-only reinstall" says 'install.sh --copy-only'
git -C "$CLONE" checkout -q HEAD~1 -- hooks/check-commits
upstream "revert: take the hook change back"
check "with the hook back: no drift in either" status_is 0 "$H"
check "nor in the other" status_is 0 "$K"
awk '{ print $0 "\r" }' "$CLONE/hooks/commit-msg" > "$K/.githooks/commit-msg"
check "a hook copy with CRLF endings is drift" status_is 1 "$K"
check "it names it" says '.githooks/commit-msg differs'
git -C "$K" checkout -q -- .githooks/commit-msg

# --- the clone's own state, and hooks that do not run (cold review,
# finding 7)
printf '# uncommitted\n' >> "$CLONE/templates/gate.conf"
check "a clone with uncommitted changes is drift" status_is 1 "$P"
check "it says so" says 'uncommitted changes'
git -C "$CLONE" checkout -q -- templates/gate.conf
SIDE="$TMP/aiwf-side"
git clone -q "$CLONE" "$SIDE"
git -C "$SIDE" checkout -q -b side
bash "$SIDE/scripts/check-drift.sh" "$P" > "$TMP/out" 2>&1
check "a clone on a branch with no upstream is drift" test "$?" -eq 1
check "it says the branch has no upstream" says 'no upstream'
check "and that it is not the default branch" says 'not the default branch'
git -C "$SIDE" checkout -q --detach
bash "$SIDE/scripts/check-drift.sh" "$P" > "$TMP/out" 2>&1
check "a clone on no branch is drift" test "$?" -eq 1
check "it says the clone is not on a branch" says 'not on a branch'
git clone -q "$P" "$TMP/p-clone"
check "a fresh clone of a project whose hooks are off is drift" status_is 1 "$TMP/p-clone"
check "it says the hooks are not active" says 'not active'
check "and gives the git config line" says 'config core.hooksPath .githooks'
git -C "$TMP/p-clone" config core.hooksPath .githooks
check "with core.hooksPath set: no drift" status_is 0 "$TMP/p-clone"
CL="$TMP/commitlint"
new_project "$CL"
cp "$CLONE/templates/commitlint.config.mjs" "$CL/commitlint.config.mjs"
commit_all "$CL" "build: add commitlint"
printf '// COMMITLINT-UPSTREAM\n' >> "$CLONE/templates/commitlint.config.mjs"
upstream "feat: change the commitlint template"
drift "$CL"
check "a copied commitlint.config.mjs is compared by a guess" says 'commitlint.config.mjs'
check "with the template's change" says '+// COMMITLINT-UPSTREAM'

# --- the clone itself, and its worktrees, are not projects (cold
# review, finding 3); make setup points its core.hooksPath at hooks/
git -C "$CLONE" config core.hooksPath hooks
check "the clone itself: exit 2" status_is 2 "$CLONE"
check "it says it is the clone" says 'is the ai-workflow clone'
session "$(json_for "$CLONE")"
check "--session in the clone is silent" silent
git -C "$CLONE" worktree add -q -b wt "$TMP/clone-wt" 2> /dev/null
check "a worktree of the clone: exit 2" status_is 2 "$TMP/clone-wt"
session "$(json_for "$TMP/clone-wt")"
check "--session in a worktree of the clone is silent" silent
git -C "$CLONE" config --unset core.hooksPath

# --- usage, and a check that writes nothing
check "an unknown option exits 2" status_is 2 --bogus "$P"
check "two directories exit 2" status_is 2 "$P" "$O"
check "a directory outside git exits 2" status_is 2 "$TMP/plain"
check "a repository that is not migrated exits 2" status_is 2 "$TMP/other"
check "the check wrote nothing in the project" test -z "$(git -C "$P" status --porcelain)"

# --- docs/upgrading.md: each entry is dated, says where it came from,
# what to do and how to tell it is done, in date order, and the check
# reads them all
NOTES="$ROOT/docs/upgrading.md"
check "docs/upgrading.md exists" test -f "$NOTES"
# entries_complete <file>: every "## " entry has a date heading and the
# three fields, and the dates do not go back
entries_complete() {
  awk '
    function close_entry() { if (title != "" && !(from && todo && done)) bad = 1 }
    /^## / {
      close_entry()
      if ($0 !~ /^## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]: ./) bad = 1
      if (substr($0, 4, 10) < last) bad = 1
      last = substr($0, 4, 10); title = $0; from = todo = done = 0; n++
      next
    }
    /^- From: / { from = 1 }
    /^- Do: / { todo = 1 }
    /^- Done when: / { done = 1 }
    END { close_entry(); exit bad || n == 0 }
  ' "$1"
}
check "every entry has a date, From, Do and Done when, in date order" entries_complete "$NOTES"
printf '## 2026-11-10: a\n\n- From: x.\n- Do: y.\n' > "$TMP/no-done.md"
refute "an entry without Done when is noticed" entries_complete "$TMP/no-done.md"
printf '## 2026-11-12: a\n\n- From: x.\n- Do: y.\n- Done when: z.\n\n## 2026-11-11: b\n\n- From: x.\n- Do: y.\n- Done when: z.\n' \
  > "$TMP/order.md"
refute "entries out of date order are noticed" entries_complete "$TMP/order.md"
for text in COMMIT_CHECK_SINCE check-walkthrough 'refs/pull/' feature-check.yml D78 D129 D137 D141 \
  D142 gate.conf '.claude/worktrees/' D151 'git push --dry-run' D152; do
  check "docs/upgrading.md covers $text" grep -qF -- "$text" "$NOTES"
done
# Run from this repository against a project without a record, the check
# lists every entry of the real file.
R="$TMP/real"
new_project "$R"
bash "$ROOT/scripts/check-drift.sh" "$R" > "$TMP/out" 2>&1
# lists_every_entry: the output holds "<date> <title>" of every entry
lists_every_entry() {
  local entry n=0
  while IFS= read -r entry; do
    says "$entry" || { printf '  not listed: %s\n' "$entry" >&2; return 1; }
    n=$((n + 1))
  done < <(sed -n 's/^## \([0-9-]*\): \(.*\)$/\1 \2/p' "$NOTES")
  [ "$n" -ge 8 ]
}
check "the check lists every entry of docs/upgrading.md" lists_every_entry

finish
