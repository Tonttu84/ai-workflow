#!/usr/bin/env bash
# Tests for the rules file and the docs that point into this repo: every
# templates/ or hooks/ file they name exists.
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

finish
