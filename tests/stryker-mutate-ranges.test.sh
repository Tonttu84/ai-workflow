#!/usr/bin/env bash
# Tests for scripts/stryker-mutate-ranges.sh: the lines changed since a
# base in JavaScript and TypeScript source files, not tests, become
# StrykerJS --mutate file:start-end entries.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp
clear_git_env # the tests run git; an outer hook's GIT_* must not steer it

RANGES="$ROOT/scripts/stryker-mutate-ranges.sh"

repo="$TMP/project"
git init -q -b main "$repo"
git -C "$repo" config user.name test
git -C "$repo" config user.email test@example.com
git -C "$repo" config core.autocrlf false
mkdir -p "$repo/src/__tests__" "$repo/e2e" "$repo/tests" "$repo/docs"
lines() { # lines <file> <n> [prefix]: writes n numbered lines
  local i
  for ((i = 1; i <= $2; i++)); do printf '%s%d\n' "${3:-line }" "$i"; done > "$1"
}
lines "$repo/src/a.ts" 10
lines "$repo/src/b.js" 10
lines "$repo/src/old.ts" 4
lines "$repo/src/gone.ts" 3
lines "$repo/src/types.d.ts" 3
lines "$repo/src/a.test.ts" 3
lines "$repo/src/__tests__/y.ts" 3
lines "$repo/e2e/x.spec.ts" 3
lines "$repo/tests/helper.ts" 3
lines "$repo/docs/readme.md" 3
git -C "$repo" add -A
git -C "$repo" commit -q -m "feat: start"
base=$(git -C "$repo" rev-parse HEAD)

# The change: lines 2-3 and 8 of a.ts edited and a line added after 8; a
# line of b.js deleted; old.ts renamed; gone.ts deleted; a new c.tsx
# committed; an untracked d.mjs; and every test, the declaration file and
# the readme edited.
awk 'NR == 2 || NR == 3 || NR == 8 { print "changed " NR; if (NR == 8) print "added"; next } { print }' \
  "$repo/src/a.ts" > "$repo/src/a.new" && mv "$repo/src/a.new" "$repo/src/a.ts"
awk 'NR != 6' "$repo/src/b.js" > "$repo/src/b.new" && mv "$repo/src/b.new" "$repo/src/b.js"
git -C "$repo" mv src/old.ts src/new.ts
git -C "$repo" rm -q src/gone.ts
lines "$repo/src/c.tsx" 3
for f in src/types.d.ts src/a.test.ts src/__tests__/y.ts e2e/x.spec.ts tests/helper.ts docs/readme.md; do
  printf 'changed\n' >> "$repo/$f"
done
git -C "$repo" add -A
git -C "$repo" commit -q -m "feat: change things"
lines "$repo/src/d.mjs" 2
printf 'line 5 again\n' >> "$repo/src/b.js" # uncommitted: line 10 of b.js

# ranges [args...]: runs the script in the repo; stdout in $TMP/out,
# stderr in $TMP/err
ranges() { (cd "$repo" && bash "$RANGES" "$@") > "$TMP/out" 2> "$TMP/err"; }
status_is() {
  local want=$1
  shift
  ranges "$@"
  [ "$?" -eq "$want" ]
}
says() { grep -qF -- "$1" "$TMP/err"; }
# has <entry>: the output, split on commas, has that entry
has() { tr ',' '\n' < "$TMP/out" | grep -qxF -- "$1"; }
mentions() { grep -qF -- "$1" "$TMP/out"; }

# --- arguments
check "--help prints the comment block and no code" help_ok "$RANGES"
check "no arguments: usage error" status_is 2
check "it prints the usage" says 'Usage'
check "an unknown base: error" status_is 2 1234567890123456789012345678901234567890
check "it names the base" says 1234567890123456789012345678901234567890
outside() { (cd "$TMP" && bash "$RANGES" "$base") > "$TMP/out" 2> "$TMP/err"; }
outside
check "outside a git work tree: error" test "$?" -eq 2

# --- the ranges
check "changed source files give ranges" status_is 0 "$base"
check "the output is one line" test "$(wc -l < "$TMP/out")" -eq 1
check "it has no spaces" test -z "$(tr -d '\n' < "$TMP/out" | tr -d -c ' ')"
check "edited lines 2-3 of a.ts" has 'src/a.ts:2-3'
check "edited line 8 and the added line 9 of a.ts" has 'src/a.ts:8-9'
check "an uncommitted line of b.js counts" has 'src/b.js:10-10'
check "a deleted line gives no range" test "$(tr ',' '\n' < "$TMP/out" | grep -c '^src/b.js:')" -eq 1
check "a renamed file is mutated whole" has 'src/new.ts:1-4'
check "a new committed file is mutated whole" has 'src/c.tsx:1-3'
check "a new untracked file is mutated whole" has 'src/d.mjs:1-2'
refute "a deleted file is not listed" mentions 'gone.ts'
refute "a declaration file is not listed" mentions 'types.d.ts'
refute "a .test. file is not listed" mentions 'a.test.ts'
refute "a __tests__ file is not listed" mentions '__tests__'
refute "an e2e spec is not listed" mentions 'x.spec.ts'
refute "a file under tests/ is not listed" mentions 'tests/helper.ts'
refute "a Markdown file is not listed" mentions 'readme.md'
check "exactly the expected entries" test "$(tr ',' '\n' < "$TMP/out" | wc -l)" -eq 6

check "a path limits the files" status_is 0 "$base" src/a.ts
check "only that file is listed" test "$(tr -d '\n' < "$TMP/out")" = 'src/a.ts:2-3,src/a.ts:8-9'
check "a path limits untracked files too" status_is 0 "$base" src/d.mjs
check "only the untracked file is listed" test "$(tr -d '\n' < "$TMP/out")" = 'src/d.mjs:1-2'

in_src() { (cd "$repo/src" && bash "$RANGES" "$base") > "$TMP/out" 2> "$TMP/err"; }
in_src
check "from a subdirectory it succeeds" test "$?" -eq 0
check "paths are relative to it, as Stryker runs there" has 'a.ts:2-3'
refute "nothing outside it is listed" mentions 'e2e'

git -C "$repo" config diff.noprefix true
check "diff.noprefix does not change the paths" status_is 0 "$base" src/a.ts
check "the path is still right" has 'src/a.ts:2-3'
git -C "$repo" config --unset diff.noprefix

# git ends a "+++" line with a tab when the path has a space
lines "$repo/src/two words.ts" 2
git -C "$repo" add "src/two words.ts"
git -C "$repo" commit -q -m "feat: a file with a space"
printf 'more\n' >> "$repo/src/two words.ts"
check "a changed file with a space in its path" status_is 0 HEAD src
check "it keeps the exact path" test "$(tr -d '\n' < "$TMP/out")" = 'src/b.js:10-10,src/two words.ts:3-3,src/d.mjs:1-2'

# --- nothing to mutate, and paths Stryker cannot take
check "no changed source line: status 1" status_is 1 HEAD docs
check "it says there is nothing to mutate" says 'nothing to mutate'
lines "$repo/src/with,comma.ts" 2
check "a path with a comma: error, since Stryker splits on commas" status_is 2 "$base"
check "it names the path" says 'with,comma.ts'

rm -f "$repo/src/with,comma.ts"

# --- a git diff that fails is an error: the untracked files alone would
# otherwise be printed as the whole change (fewer ranges, fewer mutants)
mkdir -p "$TMP/fakebin"
# shellcheck disable=SC2016
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = diff ] && exit 128; done\nexec %s "$@"\n' "$(command -v git)" > "$TMP/fakebin/git"
chmod +x "$TMP/fakebin/git"
broken_diff() { (cd "$repo" && PATH="$TMP/fakebin:$PATH" bash "$RANGES" "$base") > "$TMP/out" 2> "$TMP/err"; }
broken_diff
check "a failing git diff: error" test "$?" -eq 2
check "it says git diff failed" says 'git diff failed'
check "nothing is printed for Stryker" test ! -s "$TMP/out"

finish
