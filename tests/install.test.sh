#!/usr/bin/env bash
# Tests for hooks/install.sh: both install modes, refusals, and an
# end-to-end commit through the installed hook.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

INSTALL="$ROOT/hooks/install.sh"

new_repo() {
  git init -q -b main "$1"
  git -C "$1" config user.name test
  git -C "$1" config user.email test@example.com
}

run_install() { bash "$INSTALL" "$@" > /dev/null 2>&1; }

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
check "--force overwrites it" run_install --git-hooks --force "$TMP/d"
check "overwritten hook is ours" cmp -s "$ROOT/hooks/commit-msg" "$TMP/d/.git/hooks/commit-msg"

# Not a git repository
mkdir -p "$TMP/plain"
refute "refuses a directory that is not a git repo" run_install "$TMP/plain"

# Unknown option
refute "rejects an unknown option" run_install --bogus "$TMP/a"

finish
