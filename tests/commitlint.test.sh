#!/usr/bin/env bash
# Runs templates/commitlint.config.mjs and hooks/commit-msg over the same
# messages (the hook's test table plus a few more) and fails where they
# disagree. Opt-in: needs node and a folder, inside a git work tree, with
# @commitlint/cli and @commitlint/config-conventional installed, named by
# $COMMITLINT_DIR. Nothing is downloaded; without them the test skips.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

cli="${COMMITLINT_DIR:-}/node_modules/@commitlint/cli/cli.js"
if [ -z "${COMMITLINT_DIR:-}" ] || [ ! -f "$cli" ] || ! command -v node > /dev/null 2>&1; then
  printf '%s: SKIP: set COMMITLINT_DIR to a folder with @commitlint/cli and\n' "$(basename "$0")"
  printf '  @commitlint/config-conventional installed to compare commitlint with the hook\n'
  exit 0
fi

# A scratch repository inside COMMITLINT_DIR, so the config finds
# config-conventional in its node_modules.
TMP=$(mktemp -d "$COMMITLINT_DIR/ai-workflow-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
git init -q "$TMP"
cp "$ROOT/templates/commitlint.config.mjs" "$TMP/commitlint.config.mjs"

# verdicts <message with escapes> <editor|:>: "hook=ok|bad commitlint=ok|bad"
verdicts() {
  local h c env=(GIT_EDITOR=:)
  [ "$2" = editor ] && env=(-u GIT_EDITOR)
  printf '%b' "$1" > "$TMP/MSG"
  if (cd "$TMP" && env "${env[@]}" bash "$ROOT/hooks/commit-msg" MSG) > "$TMP/hook.out" 2>&1; then h=ok; else h=bad; fi
  if (cd "$TMP" && env "${env[@]}" timeout 60 node "$cli" --edit MSG) > "$TMP/cl.out" 2>&1; then c=ok; else c=bad; fi
  printf 'hook=%s commitlint=%s' "$h" "$c"
}
agree() { # agree <message> <editor|:>
  local v
  v=$(verdicts "$1" "$2")
  case $v in
    'hook=ok commitlint=ok' | 'hook=bad commitlint=bad') return 0 ;;
  esac
  # Known difference: commitlint passes a message that is empty once
  # comment lines are dropped; git aborts an empty message anyway.
  grep -qv '^#' "$TMP/MSG" || return 0
  printf '  %s (%s): %s\n' "$v" "$2" "$1" >&2
  sed 's/^/    /' "$TMP/cl.out" | head -5 >&2
  return 1
}

while IFS='|' read -r want msg; do
  case $want in ok | bad) mode=: ;; *@editor) mode=editor ;; *) continue ;; esac
  check "same verdict: $msg" agree "$msg" "$mode"
done < <(sed -n "/^done <<'TABLE'/,/^TABLE/p" "$ROOT/tests/commit-msg.test.sh")

# Length is counted in characters (code points), as the hook counts it.
repeat() { local i; for ((i = 0; i < $1; i++)); do printf '%b' "$2"; done; }
check "67 two-byte characters" agree "fix: $(repeat 67 '\303\244')" :
check "68 two-byte characters" agree "fix: $(repeat 68 '\303\244')" :
check "67 characters outside the BMP" agree "fix: $(repeat 67 '\360\237\230\200')" :
check "68 characters outside the BMP" agree "fix: $(repeat 68 '\360\237\230\200')" :
check "a trailing space" agree 'feat: add login form   ' :
check "a footer right under the subject" agree 'feat: add login form\nRefs: R1' :
check "a footer right under the body" agree 'feat: add login form\n\nWhy.\nRefs: R1' :

finish
