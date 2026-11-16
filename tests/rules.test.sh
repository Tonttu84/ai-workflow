#!/usr/bin/env bash
# Tests for the rules file and the docs that point into this repo: every
# templates/, hooks/, scripts/, rules/ or skills/ file they name exists,
# the always-loaded rules stay under a word cap and point to the setup
# file and the local skills, and the function limits template has the
# agreed values.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
make_tmp

RULES="$ROOT/rules/working-agreements.md"
SETUP="$ROOT/rules/setup.md"

# named_paths <file...>: every templates/, hooks/, scripts/, rules/ or
# skills/<file> named in them, one per line (a bare "templates/" names the
# folder, not a file)
named_paths() {
  grep -ohE '(^|[^A-Za-z0-9_./-])(templates|hooks|scripts|rules|skills)/[A-Za-z0-9._-]*[A-Za-z0-9]' "$@" |
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
check "every template, hook and script the rules name exists" all_exist "$ROOT" "$RULES"
check "every template, hook and script the readme names exists" all_exist "$ROOT" "$ROOT/README.md"
check "every template, hook and script the templates name exists" all_exist "$ROOT" "$ROOT"/templates/*.md
check "the setup file exists" test -f "$SETUP"
check "every template, hook and script the setup file names exists" all_exist "$ROOT" "$SETUP"
# SC2016: the backticks are Markdown, written as text.
# shellcheck disable=SC2016
printf 'See `templates/no-such-brief.md`.\n' > "$TMP/broken.md"
refute "a missing template is noticed" all_exist "$ROOT" "$TMP/broken.md" 2> /dev/null
# shellcheck disable=SC2016
printf 'Run `scripts/no-such-check.sh`.\n' > "$TMP/broken-script.md"
refute "a missing script is noticed" all_exist "$ROOT" "$TMP/broken-script.md" 2> /dev/null
# shellcheck disable=SC2016
printf 'Read `rules/no-such-file.md`.\n' > "$TMP/broken-rules.md"
refute "a missing rules file is noticed" all_exist "$ROOT" "$TMP/broken-rules.md" 2> /dev/null

# --- the always-loaded rules send the coordinator to the skills and an
# agent setting up a project to rules/setup.md (D88)
skills_list=$(local_skills)
for name in coordinating researching verifying-features; do
  check "$name is a local skill" grep -qxF "$name" <<< "$skills_list"
done
for name in $skills_list; do
  check "every file the $name skill names exists" all_exist "$ROOT" "$ROOT/skills/$name/SKILL.md"
  # shellcheck disable=SC2016
  check "the rules trigger the $name skill" grep -qF "\`$name\` skill" "$RULES"
done
# shellcheck disable=SC2016
check "the rules point to the setup file" grep -qF '`rules/setup.md`' "$RULES"
# Every brief a subagent may be handed is named in the rules it loads.
for brief in "$ROOT"/templates/*-brief.md; do
  check "the rules name templates/${brief##*/}" grep -qF "templates/${brief##*/}" "$RULES"
done
# What binds a subagent stays in the always-loaded rules: nothing it needs
# may live only in a skill.
# shellcheck disable=SC2016
for text in '--no-verify' 'Never weaken, skip or delete a test' 'deterministic check' \
  '`instruction`' '`preference`' '`idea`' 'twice' '<project>/credentials/' \
  'Locked tests' 'Refs:' 'never push without asking'; do
  check "the rules keep $text" grep -qF -- "$text" "$RULES"
done

# --- the rules load into every session, so their size is capped: raising
# the cap is a decision, not a side effect of an edit (D89)
cap=2000
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
  'lizard -C 15 -L 60 -a 5' \
  '"complexity": ["warn", { "max": 15 }]' '"max-lines-per-function": ["warn", { "max": 60' \
  '"max-params": ["warn", { "max": 5 }]' '"max-depth": ["warn", { "max": 3 }]' \
  'lizard -l GDScript -C 15 -L 60 -a 5'; do
  check "function-limits.md sets $line" sets "$LIMITS" "$line"
done
# A gate with --max-warnings 0 keeps the limits in a report-only command,
# and a report-only Lizard run accepts its exit status 1 (warnings found)
# but not a missing tool.
# SC2016: $$? is Makefile text, matched literally.
# shellcheck disable=SC2016
for text in '"lint:limits": "eslint -c eslint.limits.config.mjs ."' 'limits:' \
  '|| [ $$? -eq 1 ]' 'uvx lizard' 'python -m pip install --user lizard'; do
  check "function-limits.md has $text" grep -qF -- "$text" "$LIMITS"
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

# --- the data template is reached from the kickoff, the readme and setup
for f in templates/kickoff.md README.md rules/setup.md; do
  check "$f points to the data and ML template" grep -qF 'templates/data-science.md' "$ROOT/$f"
done
# Its pointer line names the public URL: collaborators may have no clone.
DATA="$ROOT/templates/data-science.md"
check "the data template's pointer line names its GitHub URL" \
  grep -qF '"Data and ML rules: https://github.com/Tonttu84/ai-workflow/blob/main/templates/data-science.md"' "$DATA"
for text in GroupKFold StratifiedGroupKFold 'bootstrap by group' Bland ICC MDC 'counts as fitting'; do
  check "the data template covers $text" grep -qF -- "$text" "$DATA"
done

# --- the migration steps carry the lessons of the migrations; they moved
# from the readme to rules/setup.md, the agents' procedure (D88)
# section <file> <heading>: that "## " section, up to the next one
section() { awk -v h="## $2" '$0 == h { on = 1; print; next } on && /^## / { exit } on' "$1"; }
in_migration_steps() { section "$SETUP" 'Migrating an existing project' | grep -qF -- "$1"; }
for text in 'git fetch origin' 'origin/<default branch>' 'identity' 'git ls-files -s .githooks' \
  '100755' 'COMMIT_CHECK_SINCE' "owner's decision" 'showcase'; do
  check "the migration steps mention $text" in_migration_steps "$text"
done
check "the migration steps stop at the next section" \
  test "$(section "$SETUP" 'Migrating an existing project' | grep -c '^## ')" -eq 1
# shellcheck disable=SC2016
check "the readme points to the setup file" grep -qF 'rules/setup.md' "$ROOT/README.md"

# --- rules/setup.md holds the kickoff and the repository settings
# shellcheck disable=SC2016
for text in 'templates/kickoff.md' 'before any code' 'Rust first' 'pyright' 'hooks/install.sh' \
  'templates/commit-check.yml' 'ruleset' 'squash_merge_commit_title=PR_TITLE' \
  'templates/dependabot.yml' 'security updates' 'refs/pull/' 'templates/escapes.md' \
  'templates/function-limits.md' '<project>/credentials/'; do
  check "the setup file mentions $text" grep -qF -- "$text" "$SETUP"
done

# --- fixes from the rules review of 2026-11-16
# The coordinator's delegation rule fires when it is about to edit code
# (D84), so it stays in the always-loaded rules; a skill that is not
# installed is read from the clone; a feature in a solo project ships
# from its branch (D98); the private repo holds research and metrics
# (D86); the author may dispute a finding (D79).
# shellcheck disable=SC2016
for text in 'Delegate all coding except trivial edits' 'skills/<name>/SKILL.md' \
  '.ai-workflow/' 'stays on its branch' 'research and metrics' \
  'disputes a finding with evidence' 'the approvals below'; do
  check "the rules say $text" grep -qF -- "$text" "$RULES"
done
# Paths in the rules are the clone's only where the rules and the
# ai-workflow skills and templates name them: a project has its own scripts/.
refute "the rules do not claim every scripts/ path for the clone" \
  grep -qF 'Paths under `templates/`, `hooks/`, `scripts/`' "$RULES"

# Tier 2 is a bonus everywhere, never something a project "runs" (D59, D99).
tier2_is_a_bonus() { # every file naming tier 2 calls it a bonus
  local f bad=0
  for f in "$@"; do
    grep -qi 'tier 2' "$f" || continue
    grep -qi 'bonus' "$f" || { printf '  %s: tier 2 without "bonus"\n' "$f" >&2; bad=1; }
    if grep -qiE 'runs? (tier 1 and tier 2|both)' "$f"; then
      printf '  %s: says tier 2 runs\n' "$f" >&2
      bad=1
    fi
  done
  [ "$bad" -eq 0 ]
}
check "tier 2 is a bonus wherever it is named" tier2_is_a_bonus "$RULES" "$SETUP" \
  "$ROOT/README.md" "$ROOT"/templates/*.md "$ROOT"/skills/*/SKILL.md
printf 'Tier 2 is a bonus. Showcase projects run tier 1 and tier 2.\n' > "$TMP/tier2.md"
refute "a file that says tier 2 runs is noticed" tier2_is_a_bonus "$TMP/tier2.md" 2> /dev/null
# OpenFastTrace is learned now in a showcase project (D91): an agent
# planning a showcase project reads that.
for f in rules/setup.md templates/AGENTS.md skills/verifying-features/SKILL.md; do
  check "$f says OpenFastTrace is learned in a showcase project (D91)" grep -qF 'D91' "$ROOT/$f"
done

# The gate scripts are copied into the project (install.sh --gate), and
# the setup, the skill and the readme say so (D101).
VF="$ROOT/skills/verifying-features/SKILL.md"
for text in 'install.sh --gate' '.ai-workflow/' 'feature-checks.conf'; do
  check "the setup file mentions $text" grep -qF -- "$text" "$SETUP"
done
check "the skill runs .ai-workflow/check-features.sh" grep -qF '.ai-workflow/check-features.sh' "$VF"
for text in '--gate' 'check-features.sh' 'feature-tables.awk' 'junit-cases.awk'; do
  check "the readme mentions $text" grep -qF -- "$text" "$ROOT/README.md"
done
# Scheduled mutation CI is deferred, not implied to exist (D75, D100).
for f in "$VF" "$SETUP"; do
  check "${f#"$ROOT"/} says scheduled mutation CI is deferred (D100)" grep -qF 'D100' "$f"
done
# A feature's work reaches main only after its walkthrough (D98).
check "the skill keeps a feature on its branch until the walkthrough" grep -qF 'D98' "$VF"

# Planted-bug results have a file and a table (D80, D96, D102).
CANARY="$ROOT/templates/review-canary.md"
check "the review-canary template exists" test -f "$CANARY"
check "its table has the agreed columns" \
  grep -qxF '| Date | Change | Planted bug | Caught | Reviewer model and effort |' "$CANARY"
for f in templates/review-brief.md skills/coordinating/SKILL.md "${VF#"$ROOT"/}"; do
  check "$f names <project>/metrics/review-canary.md" grep -qF '<project>/metrics/review-canary.md' "$ROOT/$f"
done
check "the review brief caps the reruns after a miss" grep -qF 'at most one rerun' "$ROOT/templates/review-brief.md"

# Subagents do see user-level skills: the readme no longer says otherwise.
refute "the skills readme no longer calls subagent skills unverified" \
  grep -qF 'was not verified' "$ROOT/skills/README.md"

# --- the agent brief keeps parallel agents' scratch files apart
check "the agent brief names scratch files by project" grep -qF '`<project>-<task>-' "$ROOT/templates/agent-brief.md"

finish
