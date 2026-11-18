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
