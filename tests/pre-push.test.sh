#!/usr/bin/env bash
# End-to-end tests for hooks/pre-push: real pushes to a bare remote,
# with the hooks installed by hooks/install.sh.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

GIT_CONFIG_GLOBAL="$TMP/global.gitconfig"
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
printf '[user]\n\tname = test\n\temail = test@example.com\n[core]\n\tautocrlf = false\n' \
  > "$GIT_CONFIG_GLOBAL"

repo="$TMP/project"
git init -q --bare -b main "$TMP/remote.git"
git init -q -b main "$repo"
git -C "$repo" remote add origin "$TMP/remote.git"
bash "$ROOT/hooks/install.sh" "$repo" > /dev/null 2>&1
# A push to main runs the gate gate.conf declares (D142); it passes here,
# and its own tests are below.
GATE='command = true'
printf '%s\n' "$GATE" > "$repo/gate.conf"

# commit <message with escapes>: a commit the commit-msg hook never saw
commit() {
  echo "$1" >> "$repo/file" && git -C "$repo" add -A &&
    git -C "$repo" commit -q --no-verify -m "$(printf '%b' "$1")"
}
q() { "$@" > /dev/null 2>&1; }
pushes() { git -C "$repo" push -q "$@" > "$TMP/push.out" 2>&1; }
remote_has() { git -C "$TMP/remote.git" rev-parse -q --verify "$1" > /dev/null; }

check "pre-push is installed next to commit-msg" test -x "$repo/.githooks/pre-push"
check "check-commits is installed next to them" test -x "$repo/.githooks/check-commits"
check "check-walkthrough is installed next to them" test -x "$repo/.githooks/check-walkthrough"
commit "chore: start"
check "a first push of good commits passes" pushes origin main
commit "feat: add the export"
commit "fix: handle an empty export"
check "a push of good commits passes" pushes origin main

tip=$(git -C "$repo" rev-parse HEAD)
for subject in "WIP" "add stuff." "fixup! feat: add the export" "squash! feat: add the export" \
  "amend! feat: add the export" "# note\nfeat: add a kept comment line"; do
  commit "$subject"
  refute "a push with a '$subject' commit is rejected" pushes origin main
  git -C "$repo" reset -q --hard "$tip"
done
check "a rejected push leaves the remote as it was" \
  test "$(git -C "$TMP/remote.git" rev-parse main)" = "$tip"

commit "WIP"
commit "feat: a good commit on top"
refute "a bad commit below a good one is caught" pushes origin main
check "the output names the bad commit" grep -q "$(git -C "$repo" rev-parse HEAD~1)" "$TMP/push.out"
git -C "$repo" reset -q --hard "$tip"

# New branches: only the commits no remote branch has yet are checked.
git -C "$repo" checkout -q -b side
check "a new branch with no new commits passes" pushes origin side
commit "feat: work on the side"
check "a new branch with good commits passes" pushes origin side
git -C "$repo" checkout -q -b other main
commit "WIP on other"
refute "a new branch with a bad commit is rejected" pushes origin other
check "the bad branch did not reach the remote" test -z "$(git -C "$TMP/remote.git" branch --list other)"
git -C "$repo" checkout -q main

# Deleting a branch checks nothing.
check "deleting a remote branch passes" pushes origin --delete side
refute "the branch is gone" remote_has refs/heads/side

# A merge commit git writes passes; a force push checks the new commits.
git -C "$repo" checkout -q -b topic
# On a file of its own: both commits appending to file would conflict,
# and leave no merge commit to push.
echo topic > "$repo/topic-file" && git -C "$repo" add topic-file &&
  git -C "$repo" commit -q --no-verify -m "feat: topic work"
git -C "$repo" checkout -q main
commit "fix: main work meanwhile"
git -C "$repo" merge -q --no-ff --no-edit topic > /dev/null 2>&1
check "git wrote a merge commit" q git -C "$repo" rev-parse -q --verify HEAD^2
check "a merge commit git wrote passes" pushes origin main
git -C "$repo" reset -q --hard HEAD~1
commit "feat: rewritten history"
check "a force push of good commits passes" pushes -f origin main
commit "WIP after the rewrite"
refute "a force push with a bad commit is rejected" pushes -f origin main
git -C "$repo" reset -q --hard HEAD~1

# History from before the rules is not checked again when pushing to a
# remote this clone knows nothing about.
old_repo() { # old_repo <dir>: a clone with a bad commit from before the hooks
  git init -q -b main "$1"
  echo old > "$1/file" && git -C "$1" add -A && git -C "$1" commit -q -m "WIP from before the rules"
}
old_repo "$TMP/known"
git init -q --bare -b main "$TMP/known-origin.git"
git -C "$TMP/known" remote add origin "$TMP/known-origin.git"
git -C "$TMP/known" push -q origin main 2> /dev/null
bash "$ROOT/hooks/install.sh" "$TMP/known" > /dev/null 2>&1
echo new >> "$TMP/known/file" && printf '%s\n' "$GATE" > "$TMP/known/gate.conf"
git -C "$TMP/known" add -A && git -C "$TMP/known" commit -q -m "feat: work under the rules"
git init -q --bare -b main "$TMP/by-url.git"
push_known() { git -C "$TMP/known" push -q "$@" > "$TMP/push.out" 2>&1; }
check "push by URL: commits another remote has are not checked again" push_known "$TMP/by-url.git" main
git init -q --bare -b main "$TMP/second.git"
git -C "$TMP/known" remote add second "$TMP/second.git"
check "first push to a newly added remote: the same" push_known second main

old_repo "$TMP/standalone"
bash "$ROOT/hooks/install.sh" "$TMP/standalone" > /dev/null 2>&1
echo new >> "$TMP/standalone/file" && printf '%s\n' "$GATE" > "$TMP/standalone/gate.conf"
git -C "$TMP/standalone" add -A && git -C "$TMP/standalone" commit -q -m "feat: work under the rules"
git init -q --bare -b main "$TMP/standalone-remote.git"
git -C "$TMP/standalone" remote add origin "$TMP/standalone-remote.git"
push_standalone() { git -C "$TMP/standalone" push -q origin "$@" > "$TMP/push.out" 2>&1; }
check "no remote-tracking refs at all: only the tip is checked" push_standalone main
check "it warns that only the tip was checked" grep -q 'only the tip' "$TMP/push.out"
git -C "$TMP/standalone" checkout -q -b bad
echo bad >> "$TMP/standalone/file" && git -C "$TMP/standalone" commit -q --no-verify -am "WIP tip"
git -C "$TMP/standalone" remote remove origin
git -C "$TMP/standalone" remote add origin "$TMP/standalone-remote.git"
refute "no remote-tracking refs and a bad tip: rejected" push_standalone bad

# The walkthrough check: in a project with docs/features/, each commit
# pushed must record a walkthrough for every finished feature, and not a
# stale one. Without docs/features/ nothing changes.
wrepo="$TMP/features"
git init -q --bare -b main "$TMP/features-remote.git"
git init -q -b main "$wrepo"
git -C "$wrepo" remote add origin "$TMP/features-remote.git"
bash "$ROOT/hooks/install.sh" "$wrepo" > /dev/null 2>&1
printf '%s\n' "$GATE" > "$wrepo/gate.conf"
wpush() { git -C "$wrepo" push -q "$@" > "$TMP/push.out" 2>&1; }
wcommit() { git -C "$wrepo" add -A && git -C "$wrepo" commit -q --no-verify --allow-empty -m "$1"; }
said() { grep -qF -- "$1" "$TMP/push.out"; }
remote_main() { git -C "$TMP/features-remote.git" rev-parse -q --verify main; }
# wfeature <Rev of F1-1> <Walkthrough: line>: one finished feature
wfeature() {
  mkdir -p "$wrepo/docs/features"
  {
    printf '# Feature F1: export\n\n'
    printf '| ID | Rev | Item | Entry point | Expected outcome | Level | Test |\n'
    printf '| --- | --- | --- | --- | --- | --- | --- |\n'
    printf '| F1-1 | %s | export | a button | a CSV | functional | e2e/a.spec.ts |\n\n' "$1"
    printf '%s\n' "$2"
  } > "$wrepo/docs/features/export.md"
}

wcommit "chore: add the hooks"
check "no docs/features: the push passes" wpush origin main
git -C "$wrepo" remote set-head origin main # what git clone records
refute "and says nothing of walkthroughs" said walkthrough
wfeature 1 'Walkthrough:'
wcommit "feat: add the export"
watched=$(git -C "$wrepo" rev-parse HEAD)
refute "a finished feature without a walkthrough: the push is refused" wpush origin main
check "it names the feature file" said docs/features/export.md
check "it says to record the walkthrough" said 'record the walkthrough'
check "the remote did not move" test "$(remote_main)" != "$watched"
wfeature 1 "Walkthrough: done 2026-11-16 at $watched"
refute "recorded in the working tree but not committed: still refused" wpush origin main
check "by the walkthrough check, before the gate" said 'record the walkthrough'
wcommit "docs: record the export walkthrough"
check "with the walkthrough committed: the push passes" wpush origin main
git -C "$wrepo" checkout -q -b side
wcommit "chore: work on the side"
git -C "$wrepo" checkout -q main
wfeature 2 "Walkthrough: done 2026-11-16 at $watched"
wcommit "feat: change the export"
refute "a Rev bump after the commit watched: refused" wpush origin main
check "it says the walkthrough is stale" said stale
check "a push of another branch is not checked by the working tree" wpush origin side
git -C "$wrepo" checkout -q --detach main~3
check "the old checkout has no docs/features" test ! -e "$wrepo/docs/features"
refute "pushed from a checkout without docs/features: main is still checked" wpush origin main
check "by the walkthrough check (an old checkout)" said stale
git -C "$wrepo" checkout -q main
git -C "$wrepo" tag -a v2 -m v2
refute "an annotated tag on a stale commit: refused" wpush origin v2
git -C "$wrepo" commit -q --no-verify --allow-empty -m "WIP"
refute "a bad message and a stale walkthrough: refused" wpush origin main
check "the message is named" said 'breaks the commit rules'
check "and so is the walkthrough" said stale
git -C "$wrepo" reset -q --hard HEAD~1
refute "one commit pushed under two names: refused" wpush origin HEAD:refs/heads/main HEAD:refs/tags/t1
check "and the walkthrough is reported once" test "$(grep -c '^check-walkthrough:' "$TMP/push.out")" -eq 1
printf '#!/bin/sh\ntouch "%s"\n' "$TMP/local.ran" > "$wrepo/.githooks/pre-push.local"
chmod +x "$wrepo/.githooks/pre-push.local"
refute "with a pre-push.local: a stale walkthrough is still refused" wpush origin main
check "by the walkthrough check (with a pre-push.local)" said stale
check "and the pre-push.local ran first" test -e "$TMP/local.ran"
rm "$wrepo/.githooks/pre-push.local"
check "deleting a branch checks nothing" wpush origin --delete side
rewatched=$(git -C "$wrepo" rev-parse HEAD)
wfeature 2 "Walkthrough: done 2026-11-17 at $rewatched"
wcommit "docs: record the export walkthrough again"
check "walked again at the new revision: the push passes" wpush origin main
check "the remote has it" test "$(remote_main)" = "$(git -C "$wrepo" rev-parse HEAD)"

# Only a push to the default branch gets the walkthrough check; a
# feature branch can be pushed at any time (owner, 2026-11-17).
git -C "$wrepo" checkout -q -b feature
wfeature 3 'Walkthrough:'
wcommit "feat: change the export again"
check "a finished feature without a walkthrough on a feature branch: the push passes" wpush origin feature
refute "and nothing is said of walkthroughs" said walkthrough
refute "the same commit pushed to the default branch: refused" wpush origin feature:main
check "it names the feature file" said docs/features/export.md
refute "the remote's main did not move" test "$(remote_main)" = "$(git -C "$wrepo" rev-parse HEAD)"
git -C "$wrepo" remote set-head origin --delete
refute "with the default branch not recorded, a feature branch is checked too" wpush origin feature:refs/heads/feature2
check "it says how to record the default branch" said 'git remote set-head origin --auto'
git -C "$wrepo" checkout -q main
wfeature 3 'Walkthrough:'
check "and a branch is checked as committed, not as the working tree is" wpush origin side:refs/heads/side2
git -C "$wrepo" checkout -q -- docs/features/export.md
git -C "$wrepo" remote set-head origin main
check "a feature branch pushed under a new name, with the default recorded, passes" wpush origin feature:refs/heads/trunk
git -C "$wrepo" remote set-head origin trunk
git -C "$wrepo" checkout -q feature
wcommit "chore: more on the feature"
refute "the recorded default branch is checked whatever its name" wpush origin feature:trunk
refute "and main is still checked: a stale or odd record only adds checks" wpush origin feature:main
check "it names the feature file (main, another default recorded)" said docs/features/export.md
git -C "$wrepo" checkout -q main

# git clone records the remote's default branch, and a later fetch does
# not move the record when the remote's default changes while the old
# branch stays. A push to main is checked all the same.
git init -q --bare -b master "$TMP/stale-remote.git"
git clone -q "$TMP/stale-remote.git" "$TMP/stale-seed" 2> /dev/null
git -C "$TMP/stale-seed" -c user.name=test -c user.email=test@example.com \
  commit -q --allow-empty -m "chore: start"
git -C "$TMP/stale-seed" push -q origin master 2> /dev/null
srepo="$TMP/stale"
git clone -q "$TMP/stale-remote.git" "$srepo" 2> /dev/null
git -C "$srepo" config user.name test
git -C "$srepo" config user.email test@example.com
git -C "$TMP/stale-remote.git" branch main master
git -C "$TMP/stale-remote.git" symbolic-ref HEAD refs/heads/main
git -C "$srepo" fetch -q origin
check "the stale record still names master" \
  test "$(git -C "$srepo" symbolic-ref refs/remotes/origin/HEAD)" = refs/remotes/origin/master
git -C "$srepo" checkout -q main
bash "$ROOT/hooks/install.sh" "$srepo" > /dev/null 2>&1
printf '%s\n' "$GATE" > "$srepo/gate.conf"
mkdir -p "$srepo/docs/features"
cp "$wrepo/docs/features/export.md" "$srepo/docs/features/export.md"
sed -i.bak 's/^Walkthrough:.*/Walkthrough:/' "$srepo/docs/features/export.md" && rm "$srepo/docs/features/export.md.bak"
git -C "$srepo" add -A
git -C "$srepo" commit -q --no-verify -m "feat: add the export"
spushed() { git -C "$srepo" push -q "$@" > "$TMP/push.out" 2>&1; }
refute "a stale default-branch record: a push to main is still checked" spushed origin main
check "it names the feature file (stale record)" said docs/features/export.md
refute "the remote's main did not move (stale record)" \
  test "$(git -C "$TMP/stale-remote.git" rev-parse main)" = "$(git -C "$srepo" rev-parse HEAD)"

# pre-push needs check-walkthrough next to it, as it needs check-commits,
# even in a project without feature files.
commit "feat: one more change"
mv "$repo/.githooks/check-walkthrough" "$TMP/check-walkthrough.kept"
refute "without check-walkthrough next to it: the push is refused" pushes origin main
check "it says to rerun install.sh" grep -q 'rerun hooks/install.sh' "$TMP/push.out"
mv "$TMP/check-walkthrough.kept" "$repo/.githooks/check-walkthrough"
check "with it back: the push passes" pushes origin main

# The gate (D142): a push to main or the recorded default branch runs the
# command of the gate.conf committed in the commit pushed, at the top of
# the repository, and is refused when the gate fails or cannot run, or
# when the working tree is not that commit. A push to another branch, a
# tag or a deletion never runs it (D128).
grepo="$TMP/gated"
git init -q --bare -b main "$TMP/gated-remote.git"
git init -q -b main "$grepo"
git -C "$grepo" remote add origin "$TMP/gated-remote.git"
bash "$ROOT/hooks/install.sh" "$grepo" > /dev/null 2>&1
ran="$TMP/gate.ran" # outside the repository: one line per run of the gate
PASS="command = echo ran >> '$ran'"
FAIL="command = echo ran >> '$ran'; exit 3"
# gpush <push arguments...>: a push from $grepo, with no gate run yet
gpush() { rm -f "$ran"; git -C "$grepo" push -q "$@" > "$TMP/push.out" 2>&1; }
# gcommit <message> [<gate.conf line>...]: commits a change, with a
# gate.conf of those lines, or none
gcommit() {
  local message=$1
  shift
  if [ "$#" -gt 0 ]; then printf '%s\n' "$@" > "$grepo/gate.conf"; else rm -f "$grepo/gate.conf"; fi
  echo "$message" >> "$grepo/file"
  git -C "$grepo" add -A && git -C "$grepo" commit -q --no-verify -m "$message"
}
gate_ran() { test -e "$ran"; }
gate_runs() { test "$(wc -l < "$ran" | tr -d ' ')" -eq "$1"; }
ghead() { git -C "$grepo" rev-parse HEAD; }
gremote() { git -C "$TMP/gated-remote.git" rev-parse -q --verify "$1"; }

printf '*.log\nvenv/\n' > "$grepo/.gitignore"
gcommit "chore: start" "$PASS"
check "gate: a push to main with a passing gate goes through" gpush origin main
check "the gate ran" gate_ran
check "the remote has the commit" test "$(gremote main)" = "$(ghead)"
check "it names the command it runs" said "echo ran >> '$ran'"
check "and says the gate passed" said 'the gate passed'

gcommit "feat: break the gate" "$FAIL"
refute "a failing gate refuses the push" gpush origin main
check "the failing gate ran" gate_ran
check "it says the gate failed" said 'the gate failed'
check "the remote did not move" test "$(gremote main)" != "$(ghead)"

gcommit "feat: need a missing tool" "command = aiwf-no-such-tool --check"
refute "a gate whose tool is missing refuses the push" gpush origin main
check "it gives the exit status of a command not found" said 'exit 127'

gcommit "feat: a gate that exits 124" "command = echo ran >> '$ran'; exit 124"
refute "a gate that exits 124 by itself refuses the push" gpush origin main
check "as a failure with its status" said 'the gate failed (exit 124)'
refute "not as a passed deadline" said 'past its deadline'

gcommit "WIP" "$FAIL"
refute "a bad commit message is refused" gpush origin main
refute "before the gate runs" gate_ran
git -C "$grepo" reset -q --hard HEAD~1

gcommit "feat: drop the gate"
refute "no gate.conf refuses the push" gpush origin main
check "it names gate.conf" said gate.conf
check "it shows an example line" said 'command = '
gcommit "feat: a gate without a command" "timeout = 60"
refute "a gate.conf without a command refuses the push" gpush origin main
check "it says the command is missing" said 'gate.conf has no command'
gcommit "feat: a gate with a bad deadline" "$PASS" "timeout = soon"
refute "a timeout that is not whole seconds refuses the push" gpush origin main
refute "and the gate does not run" gate_ran
gcommit "feat: a gate with a misspelt key" "$PASS" "comand = true"
refute "an unknown key in gate.conf refuses the push" gpush origin main
gcommit "feat: a gate set twice" "$PASS" "command = true"
refute "a key set twice refuses the push" gpush origin main
check "it says the key is set twice" said 'command is set twice'
gcommit "feat: a gate with a stray line" "$PASS" "run the tests"
refute "a line that is not '<key> = <value>' refuses the push" gpush origin main
check "it names the line" said 'gate.conf:2:'
gcommit "feat: a gate with no time" "$PASS" "timeout = 0"
refute "a timeout of 0 refuses the push" gpush origin main
check "it says the timeout is bad (0)" said "timeout must be whole seconds"
gcommit "feat: a gate with a day and a second" "$PASS" "timeout = 86401"
refute "a timeout over a day refuses the push" gpush origin main
check "it says the timeout is too long" said 'at most 86400'
gcommit "feat: a gate with a huge timeout" "$PASS" "timeout = 99999999999999999999"
refute "a timeout too large for bash refuses the push" gpush origin main
refute "and the gate does not run (huge timeout)" gate_ran
gcommit "feat: a gate with CRLF endings" "$PASS"$'\r' "timeout = 60"$'\r'
check "a gate.conf with CRLF line endings works" gpush origin main
check "and its command ran, without the CR" gate_ran
gcommit "feat: an untracked gate"
printf '%s\n' "$PASS" > "$grepo/gate.conf"
refute "a gate.conf that is not committed refuses the push" gpush origin main
refute "and is not run" gate_ran
rm "$grepo/gate.conf"

# A gate past its deadline is stopped, its children too, and the push is
# refused. Without the deadline it would pass after 30 seconds.
pids="$TMP/gate.pids"
# SC2016: the gate's shell expands $! and $$.
# shellcheck disable=SC2016
gcommit "feat: a slow gate" "command = sleep 30 & echo \$! > '$pids'; echo \$\$ >> '$pids'; wait" "timeout = 2"
started=$SECONDS
refute "a gate past its deadline refuses the push" gpush origin main
check "it is stopped at the deadline, not after the sleep" test $((SECONDS - started)) -lt 25
check "it says the deadline passed" said 'past its deadline'
alive() { local p; while read -r p; do kill -0 "$p" 2> /dev/null && return 0; done < "$pids"; return 1; }
# settle <tenths>: waits until none of the gate's processes is alive, at
# most that many tenths of a second; a dead process cannot come back, so
# this ends a fixed wait early without changing what the check sees
settle() {
  local n=0
  while alive && [ "$n" -lt "$1" ]; do sleep 0.1; n=$((n + 1)); done
}
check "the gate wrote its process IDs" test -s "$pids"
refute "and leaves no process running" alive
# A gate that ignores TERM, and its child, get KILL 10 seconds later.
# shellcheck disable=SC2016
gcommit "feat: a stubborn gate" "command = trap '' TERM; sleep 30 & echo \$! > '$pids'; echo \$\$ >> '$pids'; wait" "timeout = 2"
refute "a gate that ignores TERM refuses the push" gpush origin main
check "the stubborn gate wrote its process IDs" test -s "$pids"
refute "and KILL reaches its whole process group" alive

# Stopping the push (TERM or Ctrl-C to the hook) stops the gate's process
# group too, though it is not the hook's own.
hookpid="$TMP/gate.hook"
# interrupt <what>: pushes main, sends TERM to the hook once the gate
# (which writes the hook's PID to $hookpid) runs, and checks that the
# push fails soon after and leaves nothing of the gate running
interrupt() {
  local pushing waited=0 started
  rm -f "$hookpid" "$pids"
  gpush origin main &
  pushing=$!
  while [ ! -s "$hookpid" ] && [ "$waited" -lt 300 ]; do sleep 0.1; waited=$((waited + 1)); done
  check "$1: the gate started" test -s "$hookpid"
  started=$SECONDS
  kill -TERM "$(cat "$hookpid")" 2> /dev/null
  refute "$1: a push whose hook is stopped fails" wait "$pushing"
  check "$1: it stops within seconds, not after the sleep" test $((SECONDS - started)) -lt 20
  settle 10
  refute "$1: and the gate's process group is gone" alive
}
# shellcheck disable=SC2016
gcommit "feat: a gate to interrupt" "command = sleep 30 & echo \$! > '$pids'; echo \$\$ >> '$pids'; echo \$PPID > '$hookpid'; wait"
interrupt "a gate that stops on TERM"
# A gate that ignores TERM gets KILL a few seconds later, not at its
# deadline (an hour by default).
# shellcheck disable=SC2016
gcommit "feat: a stubborn gate to interrupt" "command = trap '' TERM; sleep 30 & echo \$! > '$pids'; echo \$\$ >> '$pids'; echo \$PPID > '$hookpid'; wait"
interrupt "a gate that ignores TERM"

# What the gate leaves running in the background when it exits is
# stopped before the tree is checked again, so it cannot write to the
# tree after that check.
# shellcheck disable=SC2016
gcommit "feat: a gate that leaves a job behind" "command = sleep 30 & echo \$! > '$pids'; (sleep 3; echo late >> file) & echo \$! >> '$pids'; echo ran >> '$ran'"
check "a gate that leaves background jobs goes through" gpush origin main
# Its job would write 3 s after it started: wait long enough to see that,
# unless every job is already gone.
settle 50
refute "its background jobs are stopped" alive
check "and did not write to the tree after the check" test -z "$(git -C "$grepo" status --porcelain)"

# The gate's input is /dev/null, not the refs git gives the hook.
gcommit "feat: a gate that reads its input" "command = [ -c /dev/stdin ] && [ ! -t 0 ] && echo ran >> '$ran'"
check "the gate's input is /dev/null" gpush origin main
check "and it ran (input)" gate_ran

# The commit pushed must be the working tree: HEAD, with nothing changed,
# staged, untracked (unless a .gitignore ignores it) or flagged.
gcommit "feat: a clean gate" "$PASS"
echo changed >> "$grepo/file"
refute "a modified tracked file refuses the push" gpush origin main
check "it says the working tree is not the commit pushed" said 'working tree'
refute "and the gate does not run on it" gate_ran
git -C "$grepo" add file
refute "a staged change refuses the push" gpush origin main
git -C "$grepo" show HEAD:file > "$grepo/file"
check "a change staged and then undone in the working tree" test -z "$(git -C "$grepo" diff --name-only HEAD)"
refute "refuses the push too: the index is not the commit" gpush origin main
check "it says the file is staged" said 'staged: file'
git -C "$grepo" reset -q --hard
echo new > "$grepo/new.txt"
refute "an untracked file nothing ignores refuses the push" gpush origin main
check "it names the file" said new.txt
echo new.txt >> "$grepo/.git/info/exclude"
refute "one that only .git/info/exclude ignores too" gpush origin main
rm "$grepo/new.txt"
git -C "$grepo" update-index --skip-worktree file
refute "a skip-worktree file refuses the push" gpush origin main
check "it says the file is flagged" said skip-worktree
git -C "$grepo" update-index --no-skip-worktree file
git -C "$grepo" update-index --assume-unchanged file
refute "an assume-unchanged file refuses the push" gpush origin main
git -C "$grepo" update-index --no-assume-unchanged file
# Only committed ignore rules may hide a file: an untracked .gitignore,
# in any case, refuses the push, unless a committed rule ignores its
# folder.
mkdir -p "$grepo/fixtures"
echo needed > "$grepo/fixtures/data.txt"
printf '*\n' > "$grepo/fixtures/.gitignore"
refute "an untracked .gitignore that hides a file refuses the push" gpush origin main
check "it names the untracked .gitignore" said 'fixtures/.gitignore'
mv "$grepo/fixtures/.gitignore" "$grepo/fixtures/.GITIGNORE"
refute "so does an untracked .GITIGNORE" gpush origin main
rm -r "$grepo/fixtures"
# Ignore rules that are not pushed do not clear its folder either: not
# .git/info/exclude, not a global excludes file.
mkdir -p "$grepo/cases"
echo needed > "$grepo/cases/data.txt"
printf '*\n' > "$grepo/cases/.gitignore"
echo cases/ >> "$grepo/.git/info/exclude"
refute "an untracked .gitignore in a folder .git/info/exclude ignores refuses the push" gpush origin main
check "it names that .gitignore (info/exclude)" said 'cases/.gitignore'
sed -i.bak '/^cases\/$/d' "$grepo/.git/info/exclude" && rm -f "$grepo/.git/info/exclude.bak"
printf 'cases/\n' > "$TMP/global-excludes"
git config --file "$GIT_CONFIG_GLOBAL" core.excludesFile "$TMP/global-excludes"
refute "so does one in a folder a global excludes file ignores" gpush origin main
check "it names that .gitignore (global excludes)" said 'cases/.gitignore'
git config --file "$GIT_CONFIG_GLOBAL" --unset core.excludesFile
rm -r "$grepo/cases"
mkdir -p "$grepo/venv"
printf '*\n' > "$grepo/venv/.gitignore"
echo local > "$grepo/venv/python"
echo debug > "$grepo/debug.log"
check "an untracked file a committed .gitignore ignores does not" gpush origin main
check "and the gate ran" gate_ran
rm -r "$grepo/debug.log" "$grepo/venv"

# The gate must not change the working tree: what it checked would not be
# what is pushed.
gcommit "feat: a gate that fixes the file" "command = echo ran >> '$ran'; echo fixed >> file"
refute "a gate that changes a tracked file refuses the push" gpush origin main
check "it says the working tree changed while the gate ran" said 'changed while the gate ran'
check "the remote did not get the commit" test "$(gremote main)" != "$(ghead)"
git -C "$grepo" checkout -q -- file
gcommit "feat: a gate that leaves a report" "command = echo ran >> '$ran'; echo report > report.txt"
refute "a gate that leaves an untracked file refuses the push" gpush origin main
rm -f "$grepo/report.txt"
gcommit "feat: a tidy gate again" "$PASS"

gcommit "feat: first" "$PASS"
first=$(ghead)
gcommit "feat: second" "$PASS"
refute "pushing a commit other than HEAD to main refuses the push" gpush origin "$first:main"
check "it says the commit pushed is not HEAD" said 'is not HEAD'
refute "and the gate does not run" gate_ran
check "pushing HEAD goes through" gpush origin main

# Other branches, tags and deletions never run the gate (D128).
git -C "$grepo" checkout -q -b side
gcommit "feat: red on a branch" "$FAIL"
check "a push to another branch with a failing gate goes through" gpush origin side
refute "without running the gate" gate_ran
echo changed >> "$grepo/file"
check "a dirty working tree does not matter there" gpush origin HEAD:refs/heads/side-dirty
git -C "$grepo" checkout -q -- file
git -C "$grepo" tag -a v1 -m v1
check "a tag push goes through" gpush origin v1
refute "without running the gate (tag)" gate_ran

# With no default branch recorded, main and master are gated, with a
# hint to record it.
git -C "$grepo" checkout -q -b master
gcommit "feat: red on master" "$FAIL"
refute "with no default branch recorded, a push to master runs the gate" gpush origin master
check "the gate ran for master" gate_ran
check "it says how to record the default branch" said 'git remote set-head origin --auto'
git -C "$grepo" checkout -q side

# The recorded default branch runs the gate, whatever its name.
check "a branch that is not yet the default one is not gated" gpush origin side:refs/heads/trunk
refute "the gate did not run for it" gate_ran
git -C "$grepo" remote set-head origin trunk
gcommit "feat: still red" "$FAIL"
refute "a push to the recorded default branch runs the gate" gpush origin side:trunk
check "the gate ran for the default branch" gate_ran
gcommit "fix: green again" "$PASS"
check "and goes through when the gate passes" gpush origin side:trunk
git -C "$grepo" checkout -q master
check "with another default branch recorded, master is not gated" gpush origin master
refute "the gate did not run for master" gate_ran
git -C "$grepo" checkout -q side

# The gate runs once, however many gated refs the push updates.
git -C "$grepo" checkout -q main
gcommit "feat: everywhere" "$PASS"
check "a push to main, the default branch and another one goes through" \
  gpush -f origin HEAD:main HEAD:trunk HEAD:refs/heads/other
check "the gate ran once" gate_runs 1
check "deleting the default branch goes through" gpush origin --delete trunk
refute "without running the gate (deletion)" gate_ran

# The gate sees no GIT_* variable that locates a repository: git exports
# GIT_DIR to a hook run in a linked worktree, and a test suite that makes
# throwaway repositories would act on the real one.
genv="$TMP/gate.env"
gtop="$TMP/gate.top"
gcommit "chore: record the environment" "command = env > '$genv'; git rev-parse --show-toplevel > '$gtop'"
wt="$TMP/gated-wt"
git -C "$grepo" worktree add -q --detach "$wt" HEAD
wt_git=$(cd "$wt" && git rev-parse --absolute-git-dir)
common=$(cd "$grepo" && git rev-parse --absolute-git-dir)
wt_push() {
  (cd "$wt" && GIT_DIR="$wt_git" GIT_WORK_TREE=. GIT_INDEX_FILE="$wt_git/index" \
    GIT_OBJECT_DIRECTORY="$common/objects" GIT_COMMON_DIR="$common" \
    git -c aiwf.probe=1 push -q origin HEAD:main) > "$TMP/push.out" 2>&1
}
check "a push from a linked worktree with GIT_* variables set goes through" wt_push
check "the gate wrote its environment" test -s "$genv"
for v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR \
  GIT_PREFIX GIT_CONFIG_PARAMETERS GIT_ALTERNATE_OBJECT_DIRECTORIES; do
  refute "the gate does not see $v" grep -q "^$v=" "$genv"
done
for v in GIT_PAGER=cat PAGER=cat GIT_TERMINAL_PROMPT=0; do
  check "the gate runs with $v, since it has no terminal" grep -qx "$v" "$genv"
done
check "the gate finds the worktree it runs in" \
  test "$(cat "$gtop")" = "$(cd "$wt" && git rev-parse --show-toplevel)"
git -C "$grepo" worktree remove --force "$wt"

# Submodules: each one's working tree must be its commit too, whatever
# .gitmodules says to ignore, and each must be checked out.
sub_origin="$TMP/sub-origin"
git init -q -b main "$sub_origin"
echo one > "$sub_origin/lib.txt"
git -C "$sub_origin" add -A && git -C "$sub_origin" commit -q -m "chore: start the library"
git -C "$grepo" -c protocol.file.allow=always submodule add -q "$sub_origin" lib > /dev/null 2>&1
gcommit "feat: add a submodule" "$PASS"
check "with a clean submodule the push goes through" gpush origin main
check "and the gate ran (submodule)" gate_ran
gcommit "feat: more next to the submodule" "$PASS"
echo new > "$grepo/lib/new.txt"
refute "an untracked file in a submodule refuses the push" gpush origin main
check "it names the file in the submodule" said 'lib/new.txt'
rm "$grepo/lib/new.txt"
git config -f "$grepo/.gitmodules" submodule.lib.ignore dirty
gcommit "feat: ignore a dirty submodule" "$PASS"
echo changed >> "$grepo/lib/lib.txt"
refute "a changed file in a submodule set to ignore = dirty refuses the push" gpush origin main
check "it names the changed file in the submodule" said 'lib/lib.txt'
git -C "$grepo/lib" checkout -q -- lib.txt
git config -f "$grepo/.gitmodules" submodule.lib.ignore all
gcommit "feat: ignore the submodule" "$PASS"
echo two >> "$grepo/lib/lib.txt"
git -C "$grepo/lib" commit -q -am "feat: two"
refute "a submodule at another commit, set to ignore = all, refuses the push" gpush origin main
git -C "$grepo/lib" reset -q --hard HEAD~1
check "with the submodule back at its commit the push goes through" gpush origin main
gcommit "feat: one more next to the submodule" "$PASS"
git -C "$grepo" submodule deinit -q -f lib > /dev/null 2>&1
refute "a submodule that is not checked out refuses the push" gpush origin main
check "it says the submodule is not checked out" said 'not checked out'
git -C "$grepo" -c protocol.file.allow=always submodule update -q --init > /dev/null 2>&1

# A submodule in a linked worktree: git exports GIT_DIR to the hook, and
# the checks inside the submodule must not follow it to the superproject.
swt="$TMP/gated-sub-wt"
git -C "$grepo" worktree add -q --detach "$swt" HEAD
git -C "$swt" -c protocol.file.allow=always submodule update -q --init > /dev/null 2>&1
echo more >> "$swt/file"
git -C "$swt" add file && git -C "$swt" commit -q --no-verify -m "feat: work in a worktree"
swt_push() { rm -f "$ran"; git -C "$swt" push -q origin HEAD:main > "$TMP/push.out" 2>&1; }
echo new > "$swt/lib/new.txt"
refute "an untracked file in a submodule of a linked worktree refuses the push" swt_push
check "it names the file in that submodule" said 'lib/new.txt'
rm "$swt/lib/new.txt"
check "with that submodule clean, the push from the worktree goes through" swt_push
check "and the gate ran (worktree submodule)" gate_ran
git -C "$grepo" worktree remove --force "$swt"
git -C "$grepo" reset -q --hard "$(gremote main)"

# A gitlink that .gitmodules does not name: git's own reason is shown.
gcommit "feat: one more before an orphan gitlink" "$PASS"
git -C "$grepo" update-index --add --cacheinfo "160000,$(git -C "$sub_origin" rev-parse HEAD),orphan"
git -C "$grepo" commit -q --no-verify -m "feat: an orphan gitlink"
refute "a gitlink with no .gitmodules entry refuses the push" gpush origin main
check "with git's reason" said 'no submodule mapping'
git -C "$grepo" reset -q --hard HEAD~1

# A pass of the gate is recorded for the commit, in git's common dir
# (D152): when the push fails after the gate (a remote that dropped the
# idle connection), pushing the same commit again runs every other check
# but not the gate. A remote whose pre-receive hook refuses stands in for
# the dropped connection.
rrepo="$TMP/recorded"
rremote="$TMP/recorded-remote.git"
git init -q --bare -b main "$rremote"
git init -q -b main "$rrepo"
git -C "$rrepo" remote add origin "$rremote"
bash "$ROOT/hooks/install.sh" "$rrepo" > /dev/null 2>&1
rran="$TMP/recorded.ran" # outside the repository: one line per run of the gate
RPASS="command = echo ran >> '$rran'"
RFAIL="command = echo ran >> '$rran'; exit 3"
records="$rrepo/.git/ai-workflow/gate-passed"
# rpush <push arguments...>: a push from $rrepo, with no gate run yet
rpush() { rm -f "$rran"; git -C "$rrepo" push -q "$@" > "$TMP/push.out" 2>&1; }
# rcommit <message> <gate.conf line>...: commits a change with that gate
rcommit() {
  local message=$1
  shift
  printf '%s\n' "$@" > "$rrepo/gate.conf"
  echo "$message" >> "$rrepo/file"
  git -C "$rrepo" add -A && git -C "$rrepo" commit -q --no-verify -m "$message"
}
# refusing on|off: the remote refuses every push after the hook, or not
refusing() {
  if [ "$1" = on ]; then
    printf '#!/bin/sh\nexit 1\n' > "$rremote/hooks/pre-receive"
    chmod +x "$rremote/hooks/pre-receive"
  else
    rm -f "$rremote/hooks/pre-receive"
  fi
}
rran_ok() { test -e "$rran"; }
recorded() { grep -q "^$1 " "$records" 2>/dev/null; }
rhead() { git -C "$rrepo" rev-parse HEAD; }

rcommit "chore: start" "$RPASS"
refusing on
refute "record: a push the remote refuses after the gate fails" rpush origin main
check "the gate ran before the remote refused" rran_ok
check "its pass is recorded for the commit" recorded "$(rhead)"
check "and the hook says to push again" said 'push again'
refusing off
check "pushing the same commit again goes through" rpush origin main
refute "without running the gate again" rran_ok
check "it says the gate passed for that commit" said "the gate passed for $(rhead)"
check "the remote has the commit (record)" \
  test "$(git -C "$rremote" rev-parse main)" = "$(rhead)"

rcommit "feat: a new commit" "$RPASS"
check "a new commit pushes" rpush origin main
check "and runs the gate" rran_ok

rcommit "feat: break the recorded gate" "$RFAIL"
refute "a failing gate refuses the push (record)" rpush origin main
refute "and records nothing" recorded "$(rhead)"
refute "the next push of that commit is refused too" rpush origin main
check "because the gate ran again" rran_ok

rcommit "feat: a slow recorded gate" "command = sleep 30" "timeout = 2"
refute "a gate past its deadline refuses the push (record)" rpush origin main
refute "and records nothing (deadline)" recorded "$(rhead)"

# A gate that passes but changes the tree is refused by the check after
# it, and that pass is not recorded: the next push runs the gate again.
rcommit "feat: a gate that fixes the file (record)" "command = echo ran >> '$rran'; echo fixed >> file"
refute "a gate that changes the tree refuses the push (record)" rpush origin main
refute "and its pass is not recorded" recorded "$(rhead)"
git -C "$rrepo" checkout -q -- file
refute "with the file restored, the next push is refused again" rpush origin main
check "because the gate ran again (tree changed)" rran_ok
git -C "$rrepo" checkout -q -- file

# A record whose last line has no newline (edited by hand) does not
# swallow the next pass.
rcommit "feat: after a record with no last newline" "$RPASS"
mkdir -p "${records%/*}"
printf '%040d 2026-01-01T00:00:00Z' 7 > "$records"
refusing on
refute "a pass after a record with no last newline, refused by the remote" rpush origin main
check "is recorded on a line of its own" recorded "$(rhead)"
refusing off
check "so the next push of that commit goes through" rpush origin main
refute "without running the gate again (no last newline)" rran_ok

# A recorded pass does not skip the other checks.
rcommit "fix: green again (record)" "$RPASS"
refusing on
refute "a pass to record before a dirty tree" rpush origin main
refusing off
echo changed >> "$rrepo/file"
refute "with a recorded pass, a changed working tree still refuses the push" rpush origin main
check "it says the working tree is not the commit pushed (record)" said 'working tree'
git -C "$rrepo" checkout -q -- file
check "with the tree clean again, the push goes through" rpush origin main
refute "on the recorded pass" rran_ok

# Linked worktrees share the record.
rcommit "feat: work for two worktrees" "$RPASS"
git -C "$rrepo" worktree add -q --detach "$TMP/recorded-wt1" HEAD
git -C "$rrepo" worktree add -q --detach "$TMP/recorded-wt2" HEAD
wtpush() { rm -f "$rran"; git -C "$1" push -q origin HEAD:main > "$TMP/push.out" 2>&1; }
refusing on
refute "a push from one linked worktree that the remote refuses" wtpush "$TMP/recorded-wt1"
check "ran the gate there" rran_ok
refusing off
check "the same commit pushed from another linked worktree goes through" wtpush "$TMP/recorded-wt2"
refute "on the pass recorded in the first one" rran_ok
git -C "$rrepo" worktree remove --force "$TMP/recorded-wt1"
git -C "$rrepo" worktree remove --force "$TMP/recorded-wt2"
git -C "$rrepo" reset -q --hard "$(git -C "$rremote" rev-parse main)"

# git push --dry-run runs the pre-push hook (git 2.49), so it runs the
# gate and records its pass without sending anything; the real push
# then skips the gate.
rcommit "feat: try it dry first" "$RPASS"
check "a dry run goes through" rpush --dry-run origin main
check "and runs the gate (dry run)" rran_ok
check "the remote did not move on the dry run" \
  test "$(git -C "$rremote" rev-parse main)" != "$(rhead)"
check "the real push then goes through" rpush origin main
refute "without running the gate again (after a dry run)" rran_ok

# The record keeps the last 20 passes.
mkdir -p "${records%/*}"
for i in $(seq 1 25); do printf '%040d 2026-01-01T00:00:00Z\n' "$i"; done > "$records"
rcommit "feat: one more pass" "$RPASS"
check "one more pass goes through" rpush origin main
check "the record keeps 20 passes" test "$(wc -l < "$records" | tr -d ' ')" -eq 20
check "the newest is the last" test "$(tail -n 1 "$records" | cut -d ' ' -f 1)" = "$(rhead)"

# check-commits is what pre-push and CI share: a range and a commit-msg hook.
cd "$repo" || exit 1
check "check-commits passes a good range" \
  q bash "$ROOT/hooks/check-commits" "$ROOT/hooks/commit-msg" "$tip~2..$tip"
commit "WIP"
refute "check-commits rejects a bad range" \
  q bash "$ROOT/hooks/check-commits" "$ROOT/hooks/commit-msg" "$tip..HEAD"
refute "check-commits fails on an invalid range" \
  q bash "$ROOT/hooks/check-commits" "$ROOT/hooks/commit-msg" "no-such-ref..HEAD"
cd "$ROOT" || exit 1

finish
