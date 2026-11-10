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
check ".sample hooks do not count" test -n "$(ls "$TMP/e2/.git/hooks"/*.sample 2> /dev/null)"
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

# Not a git repository
mkdir -p "$TMP/plain"
refute "refuses a directory that is not a git repo" run_install "$TMP/plain"

# Unknown option
refute "rejects an unknown option" run_install --bogus "$TMP/a"

finish
