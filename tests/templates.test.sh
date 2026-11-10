#!/usr/bin/env bash
# Tests for the templates that must stay in step with the hook.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

HOOK="$ROOT/hooks/commit-msg"
COMMITLINT="$ROOT/templates/commitlint.config.mjs"

# --- commitlint.config.mjs: same types and limit as the hook
hook_types() { sed -n "s/^types='\(.*\)'$/\1/p" "$HOOK"; }
hook_max() { sed -n 's/^max=\([0-9]*\)$/\1/p' "$HOOK"; }
config_types() {
  sed -n 's/^const types = \[\(.*\)\];$/\1/p' "$1" | tr -d "' " | tr ',' '|'
}
config_max() { sed -n 's/^const max = \([0-9]*\);$/\1/p' "$1"; }
matches_hook() { # matches_hook <commitlint config>
  [ -n "$(hook_types)" ] && [ "$(config_types "$1")" = "$(hook_types)" ] &&
    [ -n "$(hook_max)" ] && [ "$(config_max "$1")" = "$(hook_max)" ]
}
check "commitlint config has the hook's types and limit" matches_hook "$COMMITLINT"
sed "s/'revert'\]/'revert', 'style']/" "$COMMITLINT" > "$TMP/drift-types.mjs"
refute "a drifted type list is noticed" matches_hook "$TMP/drift-types.mjs"
sed 's/^const max = 72;$/const max = 100;/' "$COMMITLINT" > "$TMP/drift-max.mjs"
refute "a drifted limit is noticed" matches_hook "$TMP/drift-max.mjs"
for rule in "'subject-case': \[0\]" "'body-max-line-length': \[0\]" "'footer-max-line-length': \[0\]" \
  "'header-max-length': \[2, 'always', max\]" "defaultIgnores: false"; do
  check "commitlint config sets $rule" grep -q "$rule" "$COMMITLINT"
done

finish
