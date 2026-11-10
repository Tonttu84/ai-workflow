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
commit "feat: topic work"
git -C "$repo" checkout -q main
commit "fix: main work meanwhile"
git -C "$repo" merge -q --no-ff --no-edit topic > /dev/null 2>&1
check "a merge commit git wrote passes" pushes origin main
git -C "$repo" reset -q --hard HEAD~1
commit "feat: rewritten history"
check "a force push of good commits passes" pushes -f origin main
commit "WIP after the rewrite"
refute "a force push with a bad commit is rejected" pushes -f origin main
git -C "$repo" reset -q --hard HEAD~1

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
