#!/usr/bin/env bash
# Tests for hooks/install.sh: both install modes, refusals, and an
# end-to-end commit through the installed hook.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

INSTALL="$ROOT/hooks/install.sh"

# Keep the machine's own git config out of the tests.
GIT_CONFIG_GLOBAL="$TMP/global.gitconfig"
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
: > "$GIT_CONFIG_GLOBAL"

new_repo() {
  git init -q -b main "$1"
  git -C "$1" config user.name test
  git -C "$1" config user.email test@example.com
}

# run_install [options] <dir>: output kept in $TMP/install.out
run_install() { bash "$INSTALL" "$@" > "$TMP/install.out" 2>&1; }
said() { grep -q -- "$1" "$TMP/install.out"; }
hooks_path_is() { test "$(git -C "$1" config core.hooksPath)" = "$2"; }

commits_ok() { git -C "$1" commit -q --allow-empty -m "$2" > /dev/null 2>&1; }

# Default mode: .githooks/ plus core.hooksPath
new_repo "$TMP/a"
check "default install succeeds" run_install "$TMP/a"
check "hook copied to .githooks" cmp -s "$ROOT/hooks/commit-msg" "$TMP/a/.githooks/commit-msg"
check "hook is executable" test -x "$TMP/a/.githooks/commit-msg"
check "pre-push copied to .githooks" cmp -s "$ROOT/hooks/pre-push" "$TMP/a/.githooks/pre-push"
check "pre-push is executable" test -x "$TMP/a/.githooks/pre-push"
check "check-commits copied to .githooks" cmp -s "$ROOT/hooks/check-commits" "$TMP/a/.githooks/check-commits"
check "core.hooksPath is .githooks" test "$(git -C "$TMP/a" config core.hooksPath)" = .githooks
refute "bad message rejected after install" commits_ok "$TMP/a" "added stuff."
check "good message accepted after install" commits_ok "$TMP/a" "chore: start the project"
check "second install is a no-op" run_install "$TMP/a"

# Default mode refuses to take over another hooks path (husky, say)
new_repo "$TMP/b"
git -C "$TMP/b" config core.hooksPath .husky/_
refute "refuses when core.hooksPath points elsewhere" run_install "$TMP/b"
check "leaves the other hooks path alone" test "$(git -C "$TMP/b" config core.hooksPath)" = .husky/_
check "--force takes over the other hooks path" run_install --force "$TMP/b"
check "--force sets core.hooksPath to .githooks" hooks_path_is "$TMP/b" .githooks

# Default mode refuses to switch off hooks already in .git/hooks
new_repo "$TMP/e"
printf '#!/bin/sh\nexit 0\n' > "$TMP/e/.git/hooks/pre-push"
refute "refuses when .git/hooks holds a hook" run_install "$TMP/e"
check "the refusal names the hook" said pre-push
check "the refusal points to --git-hooks" said --git-hooks
refute "the refusal leaves core.hooksPath unset" hooks_path_is "$TMP/e" .githooks
check "--force installs anyway" run_install --force "$TMP/e"
check "--force sets core.hooksPath" hooks_path_is "$TMP/e" .githooks
new_repo "$TMP/e2"
has_samples() { compgen -G "$1/*.sample" > /dev/null; }
check ".sample hooks do not count" has_samples "$TMP/e2/.git/hooks"
check "install succeeds next to .sample hooks only" run_install "$TMP/e2"

# Default mode warns when it overrides a global core.hooksPath
new_repo "$TMP/g"
git config --global core.hooksPath "$TMP/global-hooks"
check "install over a global core.hooksPath succeeds" run_install "$TMP/g"
check "it warns that the global hooks path stops applying" said "global-hooks. stop running"
check "the local core.hooksPath wins" hooks_path_is "$TMP/g" .githooks
refute "--git-hooks refuses under a global core.hooksPath" run_install --git-hooks "$TMP/g"
git config --global --unset core.hooksPath

# --git-hooks refuses when core.hooksPath is set (git would ignore .git/hooks)
new_repo "$TMP/f"
git -C "$TMP/f" config core.hooksPath .husky/_
refute "--git-hooks refuses when core.hooksPath is set" run_install --git-hooks "$TMP/f"
check "nothing copied to .git/hooks" test ! -e "$TMP/f/.git/hooks/commit-msg"

# From a subdirectory: installs at the top of the repository
new_repo "$TMP/h"
mkdir -p "$TMP/h/src/deep"
check "install from a subdirectory succeeds" run_install "$TMP/h/src/deep"
check "hook lands at the top" test -x "$TMP/h/.githooks/commit-msg"
refute "bad message rejected" commits_ok "$TMP/h" "WIP"

# From a linked worktree
new_repo "$TMP/w"
commits_ok "$TMP/w" "chore: start"
git -C "$TMP/w" worktree add -q -b wt "$TMP/w-wt" 2> /dev/null
printf '#!/bin/sh\nexit 0\n' > "$TMP/w/.git/hooks/post-checkout"
refute "worktree: refuses over hooks in the shared .git/hooks" run_install "$TMP/w-wt"
rm "$TMP/w/.git/hooks/post-checkout"
check "worktree: --git-hooks install succeeds" run_install --git-hooks "$TMP/w-wt"
check "worktree: hook lands in the shared .git/hooks" test -x "$TMP/w/.git/hooks/commit-msg"
refute "worktree: bad message rejected" commits_ok "$TMP/w-wt" "WIP"
rm -f "$TMP/w/.git/hooks/commit-msg"
check "worktree: default install succeeds" run_install "$TMP/w-wt"
check "worktree: hook lands in the worktree's .githooks" test -x "$TMP/w-wt/.githooks/commit-msg"
refute "worktree: bad message rejected via .githooks" commits_ok "$TMP/w-wt" "WIP"

# A path with a space and a non-ASCII character
new_repo "$TMP/my proj ä"
check "install into a path with a space and ä" run_install "$TMP/my proj ä"
refute "bad message rejected there" commits_ok "$TMP/my proj ä" "WIP"
check "good message accepted there" commits_ok "$TMP/my proj ä" "chore: start the project"

# --git-hooks mode: copy into .git/hooks
new_repo "$TMP/c"
check "--git-hooks install succeeds" run_install --git-hooks "$TMP/c"
check "hook copied to .git/hooks" cmp -s "$ROOT/hooks/commit-msg" "$TMP/c/.git/hooks/commit-msg"
check "pre-push copied to .git/hooks" cmp -s "$ROOT/hooks/pre-push" "$TMP/c/.git/hooks/pre-push"
check "check-commits copied to .git/hooks" cmp -s "$ROOT/hooks/check-commits" "$TMP/c/.git/hooks/check-commits"
refute "--git-hooks leaves core.hooksPath unset" git -C "$TMP/c" config core.hooksPath
refute "bad message rejected via .git/hooks" commits_ok "$TMP/c" "WIP"
check "good message accepted via .git/hooks" commits_ok "$TMP/c" "chore: start the project"

# --git-hooks refuses to overwrite a different hook unless --force
new_repo "$TMP/d"
printf '#!/bin/sh\nexit 0\n' > "$TMP/d/.git/hooks/commit-msg"
refute "refuses to overwrite a different hook" run_install --git-hooks "$TMP/d"
check "the different hook is left as it was" grep -q 'exit 0' "$TMP/d/.git/hooks/commit-msg"
check "--force overwrites it" run_install --git-hooks --force "$TMP/d"
check "overwritten hook is ours" cmp -s "$ROOT/hooks/commit-msg" "$TMP/d/.git/hooks/commit-msg"

# A pre-push that is not ours (Git LFS installs one) is never overwritten,
# not even with --force: it is kept as pre-push.local, and ours runs it
# first with the same arguments and input.
fake_lfs() { # fake_lfs <file>: a pre-push that records its arguments and input
  # SC2016: the fake hook expands $* itself.
  # shellcheck disable=SC2016
  printf '#!/bin/sh\necho "args: $*" > "%s"\ncat >> "%s"\n' "$TMP/lfs.ran" "$TMP/lfs.ran" > "$1"
  chmod +x "$1"
}
q() { "$@" > /dev/null 2>&1; }
new_repo "$TMP/d2"
fake_lfs "$TMP/d2/.git/hooks/pre-push"
check "--git-hooks installs next to a foreign pre-push" run_install --git-hooks "$TMP/d2"
check "it says the foreign pre-push is chained" said pre-push.local
check "ours is now the pre-push" cmp -s "$ROOT/hooks/pre-push" "$TMP/d2/.git/hooks/pre-push"
check "the foreign one is kept as pre-push.local" grep -q lfs.ran "$TMP/d2/.git/hooks/pre-push.local"
check "a second install keeps the chain" run_install --git-hooks "$TMP/d2"
check "--force does not overwrite it either" run_install --git-hooks --force "$TMP/d2"
check "the foreign one is still pre-push.local" grep -q lfs.ran "$TMP/d2/.git/hooks/pre-push.local"
git init -q --bare -b main "$TMP/d2-remote.git"
git -C "$TMP/d2" remote add origin "$TMP/d2-remote.git"
commits_ok "$TMP/d2" "chore: start"
check "a push goes through both hooks" q git -C "$TMP/d2" push -q origin main
check "the chained pre-push got git's arguments" grep -q "^args: origin " "$TMP/lfs.ran"
check "the chained pre-push read the refs from stdin" grep -qE '^refs/heads/main [0-9a-f]+ refs/heads/main ' "$TMP/lfs.ran"
git -C "$TMP/d2" commit -q --no-verify --allow-empty -m "WIP"
refute "our check still runs after the chained one" q git -C "$TMP/d2" push -q origin main
git -C "$TMP/d2" reset -q --hard HEAD~1
printf '#!/bin/sh\nexit 1\n' > "$TMP/d2/.git/hooks/pre-push.local"
commits_ok "$TMP/d2" "chore: more"
refute "a failing chained pre-push stops the push" q git -C "$TMP/d2" push -q origin main

# The default mode still refuses while the hooks sit in .git/hooks (git
# would stop running them); moved into .githooks/, the pre-push is chained.
new_repo "$TMP/d3"
fake_lfs "$TMP/d3/.git/hooks/pre-push"
refute "default mode refuses over a pre-push in .git/hooks" run_install "$TMP/d3"
check "that refusal names pre-push" said pre-push
mkdir -p "$TMP/d3/.githooks"
mv "$TMP/d3/.git/hooks/pre-push" "$TMP/d3/.githooks/pre-push"
check "with it moved into .githooks/, the install succeeds" run_install "$TMP/d3"
check "and chains it there" grep -q lfs.ran "$TMP/d3/.githooks/pre-push.local"

# A refusal (a different commit-msg) happens before anything moves.
new_repo "$TMP/d5"
printf '#!/bin/sh\nexit 0\n' > "$TMP/d5/.git/hooks/commit-msg"
fake_lfs "$TMP/d5/.git/hooks/pre-push"
refute "a different commit-msg is refused" run_install --git-hooks "$TMP/d5"
check "the foreign pre-push has not moved" grep -q lfs.ran "$TMP/d5/.git/hooks/pre-push"
check "no pre-push.local was made" test ! -e "$TMP/d5/.git/hooks/pre-push.local"
new_repo "$TMP/d4"
check "--git-hooks install for the switch" run_install --git-hooks "$TMP/d4"
check "our own hooks in .git/hooks do not block the default mode" run_install "$TMP/d4"

# Not a git repository
mkdir -p "$TMP/plain"
refute "refuses a directory that is not a git repo" run_install "$TMP/plain"

# Help
check "--help prints the comment block and no code" help_ok "$INSTALL"

# Unknown option
refute "rejects an unknown option" run_install --bogus "$TMP/a"

finish
