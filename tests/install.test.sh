#!/usr/bin/env bash
# Tests for hooks/install.sh: both install modes, refusals, and an
# end-to-end commit through the installed hook.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

INSTALL="$ROOT/hooks/install.sh"

# Keep the machine's own git config and any outer hook's GIT_* variables
# out of the tests.
clear_git_env
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

# The hooks reach the index as executable even when chmod cannot (Git for
# Windows sets core.filemode=false); git on Linux skips a 100644 hook.
# modes_are <mode> <repo> [tree]: every .githooks file has that mode in
# the index, or in the tree given, and there are at least three
modes_are() {
  local listing
  if [ -n "${3-}" ]; then
    listing=$(git -C "$2" ls-tree -r "$3" -- .githooks)
  else
    listing=$(git -C "$2" ls-files -s -- .githooks)
  fi
  [ "$(printf '%s\n' "$listing" | grep -c .)" -ge 3 ] &&
    [ "$(printf '%s\n' "$listing" | awk '{ print $1 }' | sort -u)" = "$1" ]
}
new_repo "$TMP/fm"
git -C "$TMP/fm" config core.filemode false
check "filemode=false: install succeeds" run_install "$TMP/fm"
check "filemode=false: the hooks are 100755 in the index" modes_are 100755 "$TMP/fm"
check "it says the hooks are staged as executable" said 100755
git -C "$TMP/fm" add -A
commits_ok "$TMP/fm" "chore: add the commit hooks"
check "filemode=false: the commit records them as 100755" modes_are 100755 "$TMP/fm" HEAD
check "a later install keeps them 100755" run_install "$TMP/fm"
check "and the index still has 100755" modes_are 100755 "$TMP/fm"

# The hooks are checked out with LF endings: bash rejects a CRLF hook,
# which a core.autocrlf=true clone makes unless .gitattributes says LF.
RULE='.githooks/* text eol=lf'
eol_is() { test "$(git -C "$1" check-attr eol -- .githooks/commit-msg | sed 's/^.*: //')" = "$2"; }
rule_count() { grep -cxF "$RULE" "$1/.gitattributes" 2> /dev/null; }
new_repo "$TMP/crlf"
git -C "$TMP/crlf" config core.autocrlf true
check "autocrlf: install succeeds" run_install "$TMP/crlf"
check "it adds the LF rule to .gitattributes" test "$(rule_count "$TMP/crlf")" = 1
said_text() { grep -qF -- "$1" "$TMP/install.out"; }
check "it says so" said_text "$RULE"
check "git now takes the hooks as LF" eol_is "$TMP/crlf" lf
check "a second install succeeds" run_install "$TMP/crlf"
check "and does not repeat the rule" test "$(rule_count "$TMP/crlf")" = 1
git -C "$TMP/crlf" add -A
commits_ok "$TMP/crlf" "chore: add the commit hooks"
git -c core.autocrlf=true clone -q "$TMP/crlf" "$TMP/crlf-clone" 2> /dev/null
has_cr() { test "$(tr -d '\r' < "$1" | wc -c)" -ne "$(wc -c < "$1")"; } # Windows grep may drop CRs
printf 'a\r\n' > "$TMP/cr" && check "has_cr sees a CR" has_cr "$TMP/cr"
refute "a core.autocrlf=true clone checks the hook out without CR" has_cr "$TMP/crlf-clone/.githooks/commit-msg"
printf 'feat: add the export\n' > "$TMP/good-msg"
check "and that hook runs under bash" env GIT_EDITOR=: bash "$TMP/crlf-clone/.githooks/commit-msg" "$TMP/good-msg"
# A broader rule already covering .githooks/ is left as it is.
new_repo "$TMP/lf"
printf '* text=auto eol=lf\n' > "$TMP/lf/.gitattributes"
cp "$TMP/lf/.gitattributes" "$TMP/lf-attrs"
check "with '* text=auto eol=lf': install succeeds" run_install "$TMP/lf"
check "and leaves .gitattributes unchanged" cmp -s "$TMP/lf-attrs" "$TMP/lf/.gitattributes"
# A file without a final newline keeps its last line whole.
new_repo "$TMP/nonl"
printf '*.png binary' > "$TMP/nonl/.gitattributes"
check "no final newline: install succeeds" run_install "$TMP/nonl"
check "the old last line is intact" grep -qx '\*\.png binary' "$TMP/nonl/.gitattributes"
check "the rule is on a line of its own" test "$(rule_count "$TMP/nonl")" = 1
# A CRLF rule for everything is overridden for the hooks.
new_repo "$TMP/crlf2"
printf '* text eol=crlf\n' > "$TMP/crlf2/.gitattributes"
check "with '* text eol=crlf': install succeeds" run_install "$TMP/crlf2"
check "the hooks are LF all the same" eol_is "$TMP/crlf2" lf

# Only committed .gitattributes files count: a rule in .git/info/attributes
# or in a global core.attributesFile gives LF here but not in other clones.
new_repo "$TMP/info"
mkdir -p "$TMP/info/.git/info"
printf '%s\n' "$RULE" > "$TMP/info/.git/info/attributes"
check "an LF rule in .git/info/attributes: install succeeds" run_install "$TMP/info"
check "the rule still goes into .gitattributes" test "$(rule_count "$TMP/info")" = 1
new_repo "$TMP/glob"
printf '* text eol=lf\n' > "$TMP/global.attributes"
git config --global core.attributesFile "$TMP/global.attributes"
check "an LF rule in a global attributes file: install succeeds" run_install "$TMP/glob"
check "the rule still goes into .gitattributes" test "$(rule_count "$TMP/glob")" = 1
git config --global --unset core.attributesFile

# When the index cannot be updated, the install fails before it sets
# core.hooksPath, shows git's own error and the command, and a rerun
# once the cause is gone finishes the job.
new_repo "$TMP/fm2"
git -C "$TMP/fm2" config core.filemode false
: > "$TMP/fm2/.git/index.lock"
refute "a locked index: the install fails" run_install "$TMP/fm2"
check "it prints the command to run" said 'git update-index --add --chmod=+x -- .githooks/commit-msg'
check "it shows git's own error" said 'index\.lock'
check "it says a rerun is safe" said 'rerun'
refute "core.hooksPath is not set yet" hooks_path_is "$TMP/fm2" .githooks
rm "$TMP/fm2/.git/index.lock"
check "the rerun succeeds" run_install "$TMP/fm2"
check "the rerun sets core.hooksPath" hooks_path_is "$TMP/fm2" .githooks
check "the rerun stages 100755" modes_are 100755 "$TMP/fm2"
check "the rerun does not repeat the LF rule" test "$(rule_count "$TMP/fm2")" -le 1

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

# --copy-only: a husky project keeps husky as the hook runner. The hooks
# are copied to .githooks/ (CI reads them there), staged executable and
# given the LF rule, and core.hooksPath stays as it is.
new_repo "$TMP/husky"
git -C "$TMP/husky" config core.filemode false
git -C "$TMP/husky" config core.hooksPath .husky/_
check "--copy-only succeeds under another hooks path" run_install --copy-only "$TMP/husky"
check "--copy-only leaves core.hooksPath alone" hooks_path_is "$TMP/husky" .husky/_
for name in commit-msg pre-push check-commits; do
  check "--copy-only copies $name" cmp -s "$ROOT/hooks/$name" "$TMP/husky/.githooks/$name"
done
check "--copy-only stages them as 100755" modes_are 100755 "$TMP/husky"
check "--copy-only adds the LF rule" test "$(rule_count "$TMP/husky")" = 1
refute "--copy-only with --git-hooks is rejected" run_install --copy-only --git-hooks "$TMP/husky"
check "it names the conflict" said "exclude each other"
new_repo "$TMP/twice"
check "--git-hooks given twice is fine" run_install --git-hooks --git-hooks "$TMP/twice"
check "--copy-only given twice is fine" run_install --copy-only --copy-only "$TMP/husky"
# The README's husky recipe. Husky 9 sets core.hooksPath to .husky/_,
# whose generated hooks run the project's .husky/<hook> with sh -e; here
# a stand-in for that wrapper. The project's .husky/pre-push calls
# .githooks/pre-push with git's arguments, and its input passes through.
mkdir -p "$TMP/husky/.husky/_"
# SC2016: "$@" is for the hooks to expand.
# shellcheck disable=SC2016
printf '#!/bin/sh\nexec sh -e .husky/pre-push "$@"\n' > "$TMP/husky/.husky/_/pre-push"
chmod +x "$TMP/husky/.husky/_/pre-push"
# shellcheck disable=SC2016
printf '.githooks/pre-push "$@"\n' > "$TMP/husky/.husky/pre-push"
git init -q --bare -b main "$TMP/husky-remote.git"
git -C "$TMP/husky" remote add origin "$TMP/husky-remote.git"
git -C "$TMP/husky" add -A
git -C "$TMP/husky" commit -q --no-verify -m "chore: add the hooks"
check "husky recipe: a good push passes" q git -C "$TMP/husky" push -q origin main
git -C "$TMP/husky" commit -q --no-verify --allow-empty -m "WIP"
refute "husky recipe: a bad commit stops the push" git -C "$TMP/husky" push -q origin main 2> "$TMP/husky-push.out"
check "and the check said why" grep -q 'breaks the commit rules' "$TMP/husky-push.out"

# Not a git repository
mkdir -p "$TMP/plain"
refute "refuses a directory that is not a git repo" run_install "$TMP/plain"

# Help
check "--help prints the comment block and no code" help_ok "$INSTALL"

# Unknown option
refute "rejects an unknown option" run_install --bogus "$TMP/a"

finish
