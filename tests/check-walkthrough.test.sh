#!/usr/bin/env bash
# Tests for hooks/check-walkthrough: a feature whose items are all
# functional needs a recorded owner walkthrough (done at a commit, or a
# skip at a commit with a reason), and a walkthrough or a skip goes stale
# when an item's Rev is bumped, or an item is added, after the commit it
# names.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

WALK="$ROOT/hooks/check-walkthrough"

clear_git_env
GIT_CONFIG_GLOBAL="$TMP/global.gitconfig"
GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL GIT_CONFIG_NOSYSTEM
printf '[user]\n\tname = test\n\temail = test@example.com\n[core]\n\tautocrlf = false\n' \
  > "$GIT_CONFIG_GLOBAL"

proj="$TMP/project"
git init -q -b main "$proj"
mkdir -p "$proj/docs/features"

# row <id> <rev> <level>: one item row of a feature table
row() { printf '| %s | %s | item %s | a button | a row exists | %s | e2e/a.spec.ts |' "$1" "$2" "$1" "$3"; }
# feature <file> <walkthrough line or -> <rows...>: writes a feature file;
# "-" leaves the Walkthrough: line out altogether
feature() {
  local file=$1 walk=$2 r
  shift 2
  {
    printf '# Feature F1: export\n\nWhat it does.\n\n'
    printf '| ID | Rev | Item | Entry point | Expected outcome | Level | Test |\n'
    printf '| --- | --- | --- | --- | --- | --- | --- |\n'
    for r in "$@"; do printf '%s\n' "$r"; done
    printf '\nLocked tests: e2e at 1234567\n\n'
    [ "$walk" = - ] || printf '%s\n' "$walk"
  } > "$proj/docs/features/$file"
}
# both <walkthrough line>: export.md with two functional items at r1
both() { feature export.md "$1" "$(row F1-1 1 functional)" "$(row F1-2 1 functional)"; }
commit_all() { git -C "$proj" add -A && git -C "$proj" commit -q --no-verify --allow-empty -m "$1"; }
head_sha() { git -C "$proj" rev-parse "${1:-HEAD}"; }

# walk [args...]: runs the script in the project; stdout in $TMP/out,
# stderr in $TMP/err
walk() { (cd "$proj" && bash "$WALK" "$@") > "$TMP/out" 2> "$TMP/err"; }
status_is() {
  local want=$1
  shift
  walk "$@"
  [ "$?" -eq "$want" ]
}
says() { grep -qF -- "$1" "$TMP/err"; }
quiet() { [ ! -s "$TMP/err" ] && [ ! -s "$TMP/out" ]; }
reset_features() { rm -rf "$proj/docs/features" && mkdir -p "$proj/docs/features"; }

# --- arguments
check "--help prints the comment block and no code" help_ok "$WALK"
check "an unknown option: usage error" status_is 2 --bogus
check "it prints the usage" says 'usage'
check "two arguments: usage error" status_is 2 HEAD HEAD
check "a revision that is not a commit: error" status_is 2 no-such-ref
check "it names the revision" says no-such-ref
mkdir -p "$TMP/plain"
out_of_repo() { (cd "$TMP/plain" && GIT_CEILING_DIRECTORIES="$TMP" bash "$WALK") > "$TMP/out" 2> "$TMP/err"; }
out_of_repo
check "outside a git repository: error" test "$?" -eq 2

# --- what needs no walkthrough
rm -rf "$proj/docs"
check "no docs/features: passes" status_is 0
mkdir -p "$proj/docs/features"
printf '# Notes\n\nNo table here.\n' > "$proj/docs/features/notes.md"
check "a feature file without an item table passes" status_is 0
check "with a note naming it" says 'notes.md'
reset_features
feature export.md 'Walkthrough:' "$(row F1-1 1 functional)" "$(row F1-2 1 wired)"
check "not every item functional, empty field: passes" status_is 0
feature export.md 'Walkthrough: maybe later' "$(row F1-1 1 functional)" "$(row F1-2 1 —)"
check "not every item functional, malformed field: passes" status_is 0
cp "$ROOT/templates/feature.md" "$proj/docs/features/export.md"
check "the unfilled template passes" status_is 0
# The template with its item functional: it needs the walkthrough, and
# the examples in its comment are not taken for the field.
sed -e 's/^| F<n>-1 | 1 |\(.*\)| — |\([^|]*|\)$/| F1-1 | 1 |\1| functional |\2/' \
  "$ROOT/templates/feature.md" > "$proj/docs/features/export.md"
check "the template's item made functional" grep -q '| functional |' "$proj/docs/features/export.md"
check "the template with its item functional fails" status_is 1
edit_walk() { # edit_walk <value>: sets the template's Walkthrough: line
  sed "s/^Walkthrough:.*/Walkthrough: $1/" "$proj/docs/features/export.md" > "$TMP/f" &&
    mv "$TMP/f" "$proj/docs/features/export.md"
}
commit_all "feat: the template's feature"
template_sha=$(head_sha)
edit_walk "skipped 2026-11-16 at $template_sha: a library with no UI"
check "and passes with the skip written on its Walkthrough: line" status_is 0
edit_walk 'skipped: a library with no UI'
check "but not with a skip in the old form, without a date and commit" status_is 1

# --- all functional, nothing recorded
both 'Walkthrough:'
commit_all "feat: the export"
first=$(head_sha)
check "all functional, empty field: fails" status_is 1
check "it names the file" says 'docs/features/export.md'
check "it says what to record" says 'done YYYY-MM-DD at <commit>'
both 'Walkthrough:    '
check "a field of blanks is empty: fails" status_is 1
both -
check "all functional, no Walkthrough: line: fails" status_is 1
check "it names the file" says 'export.md'
check "it says the line is missing" says 'no Walkthrough: line'
both "Walkthrough: skipped 2026-11-16 at $first: no UI"
printf '<!--\n     Walkthrough: done 2026-11-16 at 1234567\n-->\n' >> "$proj/docs/features/export.md"
check "an indented Walkthrough: in a comment is not the field" status_is 0
both 'Walkthrough: <done YYYY-MM-DD at <commit> | skipped: <reason>>'
check "the template's placeholder left in: fails" status_is 1
# SC2016: the backticks are Markdown code, not a command.
# shellcheck disable=SC2016
feature export.md 'Walkthrough:' "$(row F1-1 1 '`functional`')" "$(row F1-2 1 Functional)"
check "functional in backticks or capitalised still counts: fails" status_is 1
feature other.md 'Walkthrough:' "$(row F2-1 1 functional)"
commit_all "feat: another feature"
other_sha=$(head_sha)
feature export.md 'Walkthrough:' "$(row F1-1 1 functional)"
feature other.md "Walkthrough: skipped 2026-11-16 at $other_sha: a library with no UI" "$(row F2-1 1 functional)"
check "one bad file among good ones: fails" status_is 1
check "it names the bad file" says 'export.md'
refute "and not the good one" says 'other.md'

# --- done at a commit
reset_features
both 'Walkthrough:'
commit_all "feat: the export"
watched=$(head_sha)
both "Walkthrough: done 2026-11-16 at $watched"
check "done at an existing commit: passes" status_is 0
check "and says nothing" quiet
both "Walkthrough: done 2026-11-16 at ${watched:0:7}"
check "done at a short SHA: passes" status_is 0
both "Walkthrough:   done 2026-11-16 at $watched   "
check "blanks around the value are fine" status_is 0
both "Walkthrough: done 2026-11-16 at 0123456789abcdef0123456789abcdef01234567"
check "done at a commit that does not exist: fails" status_is 1
check "it says the commit is not found" says 'not found'
check "it names the commit" says '0123456789abcdef'
blob=$(printf 'x\n' | git -C "$proj" hash-object -w --stdin)
both "Walkthrough: done 2026-11-16 at $blob"
check "done at an object that is not a commit: fails" status_is 1

# --- malformed fields
for bad in 'done 2026-13-01 at %s' 'done 2026-02-30 at %s' 'done 2026-02-29 at %s' \
  'done 2026-00-10 at %s' 'done 2026-11-00 at %s' 'done 2026-04-31 at %s' \
  'done 2026-2-3 at %s' 'done 26-11-16 at %s' 'done 2026/11/16 at %s' 'done at %s' \
  'done 2026-11-16' 'done 2026-11-16 %s' 'done 2026-11-16 at' 'done 2026-11-16 at HEAD' \
  'done 2026-11-16 at main' 'done 2026-11-16 at %.6s' 'done 2026-11-16 at %s and more' \
  'done' 'yes' 'Done 2026-11-16 at %s' 'skipped' 'skip: no UI' \
  'skipped: no UI' 'skipped 2026-11-16: no UI' 'skipped at %s: no UI' 'skipped 2026-11-16 at %s' \
  'skipped 2026-11-16 at %s no UI' 'skipped 2026-11-16 at HEAD: no UI' 'skipped 2026-11-16 at %.6s: no UI' \
  'skipped 2026-13-01 at %s: no UI' 'skipped 2026-02-30 at %s: no UI' 'skipped 2026/11/16 at %s: no UI' \
  'Skipped 2026-11-16 at %s: no UI' 'skipped: 2026-11-16 at %s: no UI' 'skip 2026-11-16 at %s: no UI' \
  'done 2026-11-16 at %s: no UI'; do
  # SC2059: the cases above are the format strings.
  # shellcheck disable=SC2059
  value=$(printf "$bad" "$watched")
  both "Walkthrough: $value"
  check "a malformed field fails: '$bad'" status_is 1
done
both 'Walkthrough: done 16.11.2026'
check "a malformed field says the expected form" status_is 1
check "it shows the done form" says 'done YYYY-MM-DD at <commit>'
check "and the skip form" says 'skipped YYYY-MM-DD at <commit>: <reason>'
both "Walkthrough: done 2028-02-29 at $watched"
check "a leap day in a leap year passes" status_is 0
both "Walkthrough: done 2000-02-29 at $watched"
check "2000 was a leap year" status_is 0
both "Walkthrough: done 2100-02-29 at $watched"
check "2100 is not a leap year: fails" status_is 1
both "Walkthrough: done 2026-12-31 at $watched"
check "the last day of the year passes" status_is 0
{
  both "Walkthrough: done 2026-11-16 at $watched"
  printf 'Walkthrough: skipped: changed my mind\n' >> "$proj/docs/features/export.md"
}
check "two Walkthrough: lines: fails" status_is 1
check "it says the field is there twice" says 'more than one'

# --- skipped: a date, the commit the skip covers, and a reason
both "Walkthrough: skipped 2026-11-16 at $watched: a library with no UI; the API tests cover it"
check "skipped at a commit with a reason: passes" status_is 0
check "and says nothing" quiet
both "Walkthrough: skipped 2026-11-16 at ${watched:0:7}: no UI"
check "skipped at a short SHA: passes" status_is 0
both "Walkthrough:   skipped  2026-11-16  at  $watched :   no UI   "
check "blanks around the parts are fine" status_is 0
both "Walkthrough: skipped 2026-11-16 at $watched: no UI: the API tests cover it"
check "a colon in the reason is fine" status_is 0
both "Walkthrough: skipped 2026-11-16 at $watched:"
check "skipped without a reason: fails" status_is 1
check "it asks for a reason" says 'reason'
check "it shows the skip form" says 'skipped YYYY-MM-DD at <commit>: <reason>'
both "Walkthrough: skipped 2026-11-16 at $watched:    "
check "skipped with only blanks: fails" status_is 1
both "Walkthrough: skipped 2026-11-16 at $watched: <reason>"
check "skipped with the placeholder reason: fails" status_is 1
both "Walkthrough: skipped 2026-11-16 at 0123456789abcdef0123456789abcdef01234567: no UI"
check "skipped at a commit that does not exist: fails" status_is 1
check "it says the commit is not found" says 'not found'
both "Walkthrough: skipped 2026-11-16 at $blob: no UI"
check "skipped at an object that is not a commit: fails" status_is 1
both "Walkthrough: skipped 2026-02-29 at $watched: no UI"
check "skipped on a date that does not exist: fails" status_is 1
check "it says the date is not real" says 'not a real date'
both "Walkthrough: skipped 2028-02-29 at $watched: no UI"
check "skipped on a leap day in a leap year: passes" status_is 0

# The old form, without a date and commit, fails and names the new one.
both 'Walkthrough: skipped: a library with no UI; the API tests cover it'
check "a skip in the old form: fails" status_is 1
check "it names the file" says 'export.md'
check "it says the form is old" says 'old form'
check "it names the new form" says 'skipped YYYY-MM-DD at <commit>: <reason>'
both 'Walkthrough: skipped:'
check "the old form without a reason: fails" status_is 1

# --- stale walkthroughs
reset_features
both 'Walkthrough:'
commit_all "feat: the export"
watched=$(head_sha)
feature export.md "Walkthrough: done 2026-11-16 at $watched" \
  "$(row F1-1 2 functional)" "$(row F1-2 1 functional)"
check "a Rev bump after the commit watched: fails" status_is 1
check "it names the item and both revisions" says 'F1-1 went from r1 to r2'
check "it says the walkthrough is stale" says 'stale'
check "it says to walk it again" says 'done YYYY-MM-DD at <commit>'
check "or to record a skip" says 'skipped YYYY-MM-DD at <commit>: <reason>'
feature export.md "Walkthrough: done 2026-11-16 at $watched" \
  "$(row F1-1 1 functional)" "$(row F1-2 1 functional)" "$(row F1-3 1 functional)"
check "an item added after the commit watched: fails" status_is 1
check "it names the new item" says 'F1-3 was added'
feature export.md "Walkthrough: done 2026-11-16 at $watched" "$(row F1-1 1 functional)"
check "an item dropped after the commit watched: passes" status_is 0
feature export.md "Walkthrough: done 2026-11-16 at $watched" \
  "$(row F1-1 1 functional)" "$(row F1-2 1 functional)"
commit_all "docs: record the walkthrough"
check "the same revisions as the commit watched: passes" status_is 0

# A skip goes stale the same way: what was skipped is no longer what ships.
feature export.md "Walkthrough: skipped 2026-11-16 at $watched: no UI" \
  "$(row F1-1 2 functional)" "$(row F1-2 1 functional)"
check "a skip with a Rev bump after the commit it names: fails" status_is 1
check "it names the item and both revisions" says 'F1-1 went from r1 to r2'
check "it says the skip is stale" says 'skip at'
check "and stale" says 'stale'
check "it says to walk it or skip it again" says 'skipped YYYY-MM-DD at <commit>: <reason>'
feature export.md "Walkthrough: skipped 2026-11-16 at $watched: no UI" \
  "$(row F1-1 1 functional)" "$(row F1-2 1 functional)" "$(row F1-3 1 functional)"
check "a skip with an item added after the commit it names: fails" status_is 1
check "it names the new item" says 'F1-3 was added'
feature export.md "Walkthrough: skipped 2026-11-16 at $watched: no UI" "$(row F1-1 1 functional)"
check "a skip with an item dropped after the commit it names: passes" status_is 0
feature export.md "Walkthrough: skipped 2026-11-16 at $watched: no UI" \
  "$(row F1-1 x functional)" "$(row F1-2 1 functional)"
check "a skip with a bad Rev: fails" status_is 1
check "it names the bad Rev" says '"x"'

# Levels rise after the commit watched: not stale, the items are the same.
reset_features
feature export.md 'Walkthrough:' "$(row F1-1 1 wired)" "$(row F1-2 1 substantive)"
commit_all "feat: wire the export"
watched=$(head_sha)
both "Walkthrough: done 2026-11-16 at $watched"
check "only the Levels changed since the commit watched: passes" status_is 0

# The feature file did not exist at the commit watched.
reset_features
commit_all "chore: no features yet"
early=$(head_sha)
both "Walkthrough: done 2026-11-16 at $early"
check "a commit from before the feature file: fails" status_is 1
check "it says the file was not there" says 'not exist'
both "Walkthrough: skipped 2026-11-16 at $early: no UI"
check "a skip at a commit from before the feature file: fails" status_is 1
check "it says the file was not there" says 'not exist'

# A walkthrough recorded again after a Rev bump passes.
reset_features
feature export.md 'Walkthrough:' "$(row F1-1 2 functional)" "$(row F1-2 1 functional)"
commit_all "feat: the export, second revision"
rewatched=$(head_sha)
feature export.md "Walkthrough: done 2026-11-17 at $rewatched" \
  "$(row F1-1 2 functional)" "$(row F1-2 1 functional)"
check "walked again at the bumped revision: passes" status_is 0

# A skip recorded at a commit after a Rev bump passes too: the owner
# decided on what ships. One recorded before the bump is stale.
feature export.md 'Walkthrough:' "$(row F1-1 3 functional)" "$(row F1-2 1 functional)"
commit_all "feat: the export, third revision"
third=$(head_sha)
feature export.md "Walkthrough: skipped 2026-11-18 at $third: covered by the API tests" \
  "$(row F1-1 3 functional)" "$(row F1-2 1 functional)"
check "a skip at a commit after a Rev bump: passes" status_is 0
feature export.md "Walkthrough: skipped 2026-11-18 at $rewatched: covered by the API tests" \
  "$(row F1-1 3 functional)" "$(row F1-2 1 functional)"
check "a skip at a commit before a Rev bump: fails" status_is 1
check "it names the item and both revisions" says 'F1-1 went from r2 to r3'

# --- table problems
reset_features
printf '| ID | Rev | Item | Test |\n| --- | --- | --- | --- |\n| F1-1 | 1 | a | b |\n\nWalkthrough:\n' \
  > "$proj/docs/features/export.md"
check "an item table without a Level column: fails" status_is 1
check "it says the Level column is missing" says 'Level'
feature export.md "Walkthrough: done 2026-11-16 at $rewatched" "$(row F1-1 x functional)" "$(row F1-2 1 functional)"
check "all functional with a bad Rev: fails" status_is 1
check "it names the bad Rev" says '"x"'
feature export.md 'Walkthrough:' "$(row F1-1 1 functional)" '| F1-2 | 1 | a short row |'
check "a row too short to have a Level is not functional" status_is 0
# Read without the escape, the Level column of F1-2 would be "d".
feature export.md 'Walkthrough:' "$(row F1-1 1 functional)" "| F1-2 | 1 | a \\| b | c | d | functional | e |"
check "an escaped pipe in a cell does not shift the Level column" status_is 1

# --- CRLF line endings
reset_features
crlf() { sed 's/$/\r/' "$proj/docs/features/export.md" > "$TMP/crlf" && mv "$TMP/crlf" "$proj/docs/features/export.md"; }
has_cr() { test "$(tr -d '\r' < "$1" | wc -c)" -ne "$(wc -c < "$1")"; }
both 'Walkthrough:' && crlf
check "the CRLF fixture has CRs" has_cr "$proj/docs/features/export.md"
check "CRLF, all functional, empty field: fails" status_is 1
commit_all "feat: the export, written on Windows"
crlf_watched=$(head_sha)
both "Walkthrough: done 2026-11-16 at $crlf_watched" && crlf
check "CRLF, done at an existing commit: passes" status_is 0
both "Walkthrough: skipped 2026-11-16 at $crlf_watched: no UI" && crlf
check "CRLF, skipped with a reason: passes" status_is 0
both "Walkthrough: skipped 2026-11-16 at $crlf_watched:" && crlf
check "CRLF, skipped without a reason: fails" status_is 1
both 'Walkthrough: skipped: no UI' && crlf
check "CRLF, a skip in the old form: fails" status_is 1
feature export.md "Walkthrough: done 2026-11-16 at $crlf_watched" \
  "$(row F1-1 2 functional)" "$(row F1-2 1 functional)" && crlf
check "CRLF, a Rev bump after a CRLF commit: fails" status_is 1
feature export.md "Walkthrough: skipped 2026-11-16 at $crlf_watched: no UI" \
  "$(row F1-1 2 functional)" "$(row F1-2 1 functional)" && crlf
check "CRLF, a skip with a Rev bump after a CRLF commit: fails" status_is 1

# --- checking a commit instead of the working tree (what pre-push does)
reset_features
both 'Walkthrough:'
commit_all "feat: the export"
unwalked=$(head_sha)
both "Walkthrough: done 2026-11-16 at $unwalked"
check "the working tree, walkthrough recorded but not committed: passes" status_is 0
check "the commit, which has no walkthrough: fails" status_is 1 "$unwalked"
check "it names the file" says 'export.md'
commit_all "docs: record the walkthrough"
walked=$(head_sha)
both 'Walkthrough:'
check "the committed walkthrough passes at its commit" status_is 0 "$walked"
check "though the working tree has lost it" status_is 1
check "a commit before docs/features existed: passes" status_is 0 "$early"
check "HEAD works as a revision" status_is 0 HEAD
feature export.md "Walkthrough: done 2026-11-16 at $unwalked" \
  "$(row F1-1 2 functional)" "$(row F1-2 1 functional)"
commit_all "feat: change the export"
check "a committed Rev bump after the commit watched: fails" status_is 1 HEAD
crlf && commit_all "chore: CRLF"
check "the same, committed with CRLF: fails" status_is 1 HEAD

# From a subdirectory, the repository's docs/features is checked.
mkdir -p "$proj/src/deep"
sub() { (cd "$proj/src/deep" && bash "$WALK" "$@") > "$TMP/out" 2> "$TMP/err"; }
sub
check "run from a subdirectory: still fails on the stale file" test "$?" -eq 1

# A committed skip is checked at its commit like a done walkthrough.
reset_features
both 'Walkthrough:'
commit_all "feat: the export"
unskipped=$(head_sha)
both "Walkthrough: skipped 2026-11-16 at $unskipped: no UI"
commit_all "docs: record the skip"
check "a committed skip at the current revisions: passes" status_is 0 HEAD
feature export.md "Walkthrough: skipped 2026-11-16 at $unskipped: no UI" \
  "$(row F1-1 2 functional)" "$(row F1-2 1 functional)"
commit_all "feat: change the export"
check "a committed Rev bump after the skip's commit: fails" status_is 1 HEAD
check "it says the skip is stale" says 'stale'
both 'Walkthrough: skipped: no UI'
commit_all "docs: an old-form skip"
check "a committed skip in the old form: fails" status_is 1 HEAD

finish
