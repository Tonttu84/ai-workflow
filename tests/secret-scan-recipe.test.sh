#!/usr/bin/env bash
# Tests for the secret scan's pre-commit recipe in rules/setup.md ("The
# secret scan"): the hook's lines are taken from the file, not copied,
# and run as a pre-commit hook in throwaway repositories, with a
# stand-in for the scanner. The hook must refuse a staged file whose
# working-tree copy differs from the staged one, since a scanner given
# paths reads the working-tree copy (D185), and let ordinary commits
# through.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

SETUP="$ROOT/rules/setup.md"

clear_git_env
GIT_CONFIG_GLOBAL="$TMP/global.gitconfig"
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
printf '[user]\n\tname = test\n\temail = test@example.com\n[core]\n\tautocrlf = false\n[init]\n\tdefaultBranch = main\n[protocol "file"]\n\tallow = always\n' \
  > "$GIT_CONFIG_GLOBAL"

# hook_lines: the hook's lines of the secret scan's recipe, from its
# "# the hook:" comment to its "# the gate:" comment, dedented
hook_lines() {
  awk '$0 == "## The secret scan" { on = 1; next } on && /^## / { exit } on' "$SETUP" |
    awk '/^ *# the hook:/ { on = 1; next } /^ *# the gate:/ { exit } on { sub(/^  /, ""); print }'
}
SCANNER='npx --no -- secretlint --no-gitignore --no-glob'
SCAN="$TMP/scan"
# The stand-in scanner: fails on a file that holds FAKEKEY, as a real
# one fails on a key; it reads the paths it is given, as secretlint does.
cat > "$SCAN" << 'EOF'
#!/usr/bin/env bash
for f in "$@"; do
  if grep -q FAKEKEY -- "$f" 2> /dev/null; then echo "scan: a key in $f" >&2; exit 1; fi
done
EOF
chmod +x "$SCAN"
HOOK="$TMP/hooks/pre-commit"
mkdir -p "$TMP/hooks"
{
  printf '#!/usr/bin/env bash\n'
  hook_lines | awk -v s="$SCANNER" -v r="\"$SCAN\"" '{ i = index($0, s); if (i) $0 = substr($0, 1, i - 1) r substr($0, i + length(s)); print }'
} > "$HOOK"
chmod +x "$HOOK"
check "the recipe has hook lines" test "$(hook_lines | grep -c .)" -ge 2
check "the hook runs the stand-in for the scanner once" test "$(grep -cF "\"$SCAN\"" "$HOOK")" -eq 1
check "the hook refuses before it scans" grep -qF 'exit 1' "$HOOK"

n=0
# new_repo: a fresh repository with one commit and the hook on; sets R
new_repo() {
  n=$((n + 1))
  R="$TMP/repo$n"
  git init -q "$R"
  printf 'base\n' > "$R/base.txt"
  git -C "$R" add base.txt
  git -C "$R" commit -qm 'chore: base'
  git -C "$R" config core.hooksPath "$TMP/hooks"
}
# commits <git commit args...>: the commit in $R goes through; its
# stderr is kept in $TMP/err
commits() {
  local before
  before=$(git -C "$R" rev-parse HEAD)
  git -C "$R" commit -q "$@" > /dev/null 2> "$TMP/err" && [ "$(git -C "$R" rev-parse HEAD)" != "$before" ]
}
# refused_unstaged <git commit args...>: the hook refuses the commit for
# unstaged changes, before the scanner runs, and HEAD stays
refused_unstaged() {
  ! commits "$@" && grep -qF 'stage the whole file' "$TMP/err" && ! grep -qF 'scan: ' "$TMP/err"
}
# refused_by_scan <file> <git commit args...>: the scanner refuses the
# commit for a key in the file
refused_by_scan() {
  local file=$1
  shift
  ! commits "$@" && grep -qF "scan: a key in $file" "$TMP/err"
}

new_repo
printf 'FAKEKEY\n' > "$R/k.txt"
git -C "$R" add k.txt
check "a staged key is refused by the scan" refused_by_scan k.txt -m 'feat: k'

new_repo
printf 'FAKEKEY\n' > "$R/k.txt"
git -C "$R" add k.txt
printf 'clean\n' > "$R/k.txt"
check "a key staged and then overwritten is refused" refused_unstaged -m 'feat: k'

new_repo
printf 'FAKEKEY\n' > "$R/k.txt"
git -C "$R" add k.txt
rm "$R/k.txt"
check "a key staged and then deleted is refused" refused_unstaged -m 'feat: k'

new_repo
printf 'x\n' > "$R/x.txt"
git -C "$R" add x.txt
git -C "$R" commit -qm 'chore: x' --no-verify
printf 'fine\n' > "$R/[x].txt"
git -C "$R" add '[x].txt'
printf 'changed\n' > "$R/x.txt"
check "a staged [x].txt beside a changed, unstaged x.txt goes through" commits -m 'feat: brackets'

new_repo
printf 'changed\n' > "$R/base.txt"
check "git commit -a goes through" commits -a -m 'feat: all'

new_repo
printf 'changed\n' > "$R/base.txt"
printf 'other\n' > "$R/other.txt"
git -C "$R" add other.txt
printf 'other, changed\n' > "$R/other.txt"
check "git commit <path> goes through" commits -m 'feat: one path' -- base.txt

# A submodule: the gitlink is what is committed, so a submodule whose
# HEAD moved after `git add` is refused like a changed file.
new_repo
S="$TMP/sub-origin"
git init -q "$S"
printf 's\n' > "$S/s.txt"
git -C "$S" add s.txt
git -C "$S" commit -qm 'chore: s'
git -C "$R" submodule --quiet add "$S" sub 2> /dev/null
git -C "$R" commit -qm 'chore: add sub' --no-verify
git -C "$R/sub" commit -q --allow-empty -m 'chore: one'
git -C "$R" add sub
git -C "$R/sub" commit -q --allow-empty -m 'chore: two'
check "a submodule whose HEAD moved after staging is refused" refused_unstaged -m 'feat: sub'

finish
