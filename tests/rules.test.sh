#!/usr/bin/env bash
# Tests for the rules file and the docs that point into this repo: every
# templates/ or hooks/ file they name exists, the rules stay under a word
# cap, and the function limits template has the agreed values.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

RULES="$ROOT/rules/working-agreements.md"

# named_paths <file...>: every templates/<file> or hooks/<file> named in
# them, one per line (a bare "templates/" names the folder, not a file)
named_paths() {
  grep -ohE '(^|[^A-Za-z0-9_./-])(templates|hooks)/[A-Za-z0-9._-]*[A-Za-z0-9]' "$@" |
    sed -E 's/^[^a-z]//' | sort -u
}
# all_exist <root> <file...>: every path named in the files exists under root
all_exist() {
  local root=$1 p missing=0
  shift
  while IFS= read -r p; do
    [ -e "$root/$p" ] || { printf '  missing: %s\n' "$p" >&2; missing=1; }
  done < <(named_paths "$@")
  [ "$missing" -eq 0 ]
}

check "the rules name some templates" test "$(named_paths "$RULES" | grep -c '^templates/')" -ge 5
check "every template and hook the rules name exists" all_exist "$ROOT" "$RULES"
check "every template and hook the readme names exists" all_exist "$ROOT" "$ROOT/README.md"
check "every template and hook the templates name exists" all_exist "$ROOT" "$ROOT"/templates/*.md
# SC2016: the backticks are Markdown, written as text.
# shellcheck disable=SC2016
printf 'See `templates/no-such-brief.md`.\n' > "$TMP/broken.md"
refute "a missing template is noticed" all_exist "$ROOT" "$TMP/broken.md" 2> /dev/null

# --- the rules load into every session, so their size is capped: raising
# the cap is a decision, not a side effect of an edit
cap=1600
under_cap() { [ "$(wc -w < "$1")" -le "$cap" ]; }
check "the rules file stays under $cap words" under_cap "$RULES"
{ cat "$RULES"; yes word | head -n "$cap"; } > "$TMP/long.md"
refute "a rules file over the cap is noticed" under_cap "$TMP/long.md"

# --- function-limits.md: every stack gets the agreed starting values
LIMITS="$ROOT/templates/function-limits.md"
# sets <file> <text>: the text is in the file and the number it ends with
# is whole there (not followed by another digit or a decimal point)
sets() {
  awk -v t="$2" '
    { i = index($0, t) }
    i && substr($0, i + length(t), 1) !~ /[0-9.]/ { found = 1 }
    END { exit !found }
  ' "$1"
}
for line in "'sonarjs/cognitive-complexity': ['warn', 15]" "complexity: ['warn', 15]" \
  "'max-lines-per-function': ['warn', { max: 60" "'max-params': ['warn', 5]" "'max-depth': ['warn', 3]" \
  'max-complexity = 15' 'max-args = 5' \
  'cognitive-complexity-threshold = 15' 'too-many-lines-threshold = 60' \
  'too-many-arguments-threshold = 5' 'excessive-nesting-threshold = 5' \
  'lizard -C 15 -L 60 -a 5'; do
  check "function-limits.md sets $line" sets "$LIMITS" "$line"
done
sed 's/^max-args = 5 /max-args = 50/' "$LIMITS" > "$TMP/limits-50.md"
check "the drifted copy differs" test -n "$(diff "$LIMITS" "$TMP/limits-50.md")"
refute "a drifted value (5 to 50) is noticed" sets "$TMP/limits-50.md" 'max-args = 5'
# clang-tidy: each threshold key is followed by the agreed value
tidy_value() { grep -A1 -F -- "key: $1" "$LIMITS" | sed -n 's/^ *value: //p'; }
check "clang-tidy: 60 lines" test "$(tidy_value readability-function-size.LineThreshold)" = 60
check "clang-tidy: 5 parameters" test "$(tidy_value readability-function-size.ParameterThreshold)" = 5
check "clang-tidy: nesting 4 (the body is level 1)" test "$(tidy_value readability-function-size.NestingThreshold)" = 4
check "clang-tidy: cognitive 15" test "$(tidy_value readability-function-cognitive-complexity.Threshold)" = 15
check "the review brief checks over-splitting" grep -q 'single-use helper' "$ROOT/templates/review-brief.md"

finish
