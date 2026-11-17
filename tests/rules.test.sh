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
    if grep -i 'tier' "$f" | grep -qiE 'runs? (tier 1 and tier 2|both)'; then
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

# --- fixes from the second docs review of 2026-11-17
COORD="$ROOT/skills/coordinating/SKILL.md"
AGENTS_T="$ROOT/templates/AGENTS.md"
HARDEN="$ROOT/templates/hardening-brief.md"
DOCS=("$RULES" "$SETUP" "$ROOT/README.md" "$ROOT"/templates/*.md "$ROOT"/skills/*/SKILL.md "$ROOT/hooks/install.sh")
# The feature checks and the walkthrough check act only on pushes to main;
# a feature branch may be pushed for backup and review fixes (D114).
# shellcheck disable=SC2016
check "the rules run the feature checks before a push to main" grep -qF 'before a push to `main`' "$RULES"
for f in "$RULES" "$VF"; do
  refute "${f#"$ROOT"/} no longer says 'for backup at any time'" grep -qF 'for backup at any time' "$f"
done
refute "the skill's push gate is not 'on every push'" grep -qF '## The push gate, on every push' "$VF"
check "the setup file says how to record the default branch" grep -qF 'git remote set-head origin --auto' "$SETUP"
# A feature branch starts at the feature file; a change to an item is
# feature work; hardening holds the merge (findings 3, 4, 5).
check "the skill's branch starts at the feature file" grep -qF 'from the feature file to the walkthrough' "$VF"
for f in "$VF" "$AGENTS_T"; do
  check "${f#"$ROOT"/} calls a change to an item feature work" grep -qF 'adds or revises a feature item is feature work' "$f"
done
for f in "$VF" "$COORD" "$HARDEN"; do
  check "${f#"$ROOT"/} says a pending skip holds the merge" grep -qF 'holds the merge' "$f"
done
refute "the hardening brief no longer runs after the feature has landed" grep -qF 'has landed' "$HARDEN"
refute "coordinating no longer hardens after a feature lands" grep -qF 'After each feature lands' "$COORD"
# OpenFastTrace is learned in one showcase project the owner chooses, and
# every project keeps the planted-bug record (finding 6, D117).
for f in "$SETUP" "$AGENTS_T" "$VF" "$COORD" "$ROOT/README.md"; do
  check "${f#"$ROOT"/} learns OpenFastTrace in one showcase project" grep -qF 'one showcase project' "$f"
done
refute "the skill no longer has every showcase project trace with OFT" \
  grep -qF 'A showcase project also traces with OpenFastTrace' "$VF"
for f in "$AGENTS_T" "$COORD"; do
  check "${f#"$ROOT"/} says every project keeps the planted-bug record" grep -qF 'every project keeps' "$f"
done
# --base is the branch the work merges into (finding 8).
no_pushed_to_base() { ! grep -nE 'the branch (pushed to|the push goes to)' "$@"; }
check "no doc gives --base as the branch pushed to" no_pushed_to_base "${DOCS[@]}"
for f in "$VF" "$AGENTS_T" "$ROOT/hooks/install.sh"; do
  check "${f#"$ROOT"/} says --base origin/main" grep -qF -- '--base origin/main' "$f"
done
# The reviewer writes its verdict to a file; the coordinator posts it
# (finding 9).
check "the rules have the reviewer write its verdict to a file" grep -qF 'writes its verdict to a file' "$RULES"
check "the review brief has the reviewer post nothing" grep -qF 'post nothing' "$ROOT/templates/review-brief.md"
refute "the review brief no longer has the reviewer post on the PR" \
  grep -qF 'Post it where the author will see it' "$ROOT/templates/review-brief.md"
# Casual research is the coordinator's own (finding 10, D64).
refute "coordinating no longer delegates a lookup without a brief" \
  grep -qF 'give a general-purpose agent the question' "$COORD"
# Setup creates the count file, turns on JUnit reports and fetches full
# history (finding 11).
for text in 'check-test-count.sh --help' 'JUnit' 'fetch-depth: 0' 'gh repo create'; do
  check "the setup file mentions $text" grep -qF -- "$text" "$SETUP"
done
# No claim that CI runs the gate scripts while no template does (finding 12).
for f in "$ROOT/README.md" "$ROOT/hooks/install.sh"; do
  refute "${f#"$ROOT"/} no longer says CI runs check-features.sh" grep -qiE 'gate, (its )?CI and every' "$f"
done
# The research reports name the rows they fed (finding 13).
for f in "$ROOT"/docs/research/*.md; do
  check "${f#"$ROOT"/} names the decision it fed" grep -qE '^Feeds: .*D[0-9]+' "$f"
  refute "${f#"$ROOT"/} is no longer 'to be decided'" grep -qF '(to be decided)' "$f"
done
# A project's AGENTS.md names its own copy of the trace check (finding 14).
refute "the AGENTS template does not name the clone's check-trace-links.sh" \
  grep -qF '`scripts/check-trace-links.sh`' "$AGENTS_T"
check "the AGENTS template names .ai-workflow/check-trace-links.sh" \
  grep -qF '.ai-workflow/check-trace-links.sh' "$AGENTS_T"
# The script changes reach the docs: citations at a revision, the exact
# lock line, the test file first in the Test cell.
for f in "$VF" "$ROOT/templates/trace-brief.md"; do
  check "${f#"$ROOT"/} runs check-citations.sh --rev" grep -qF 'check-citations.sh --rev' "$f"
done
check "the test-writer brief writes the lock line at the start of a line" \
  grep -qF 'at the start of a line' "$ROOT/templates/test-writer-brief.md"
check "the test-writer brief puts the test file first in the Test cell" \
  grep -qF 'the file first' "$ROOT/templates/test-writer-brief.md"
# Ideas left for later have a file, and it is named where an agent parks
# one and in the layout.
IDEAS="$ROOT/docs/ideas.md"
check "docs/ideas.md exists" test -f "$IDEAS"
for f in "$COORD" "$ROOT/README.md"; do
  check "${f#"$ROOT"/} names docs/ideas.md" grep -qF 'docs/ideas.md' "$f"
done
# every_idea_complete <file>: each "## " entry has the five fields
every_idea_complete() {
  awk '
    /^## / { if (n) check(); n++; seen = "" ; next }
    /^- (Date|Source|What|Why not now|Revisit when): / { f = $0; sub(/^- /, "", f); sub(/: .*/, "", f); seen = seen "|" f }
    function check() { if (seen !~ /Date/ || seen !~ /Source/ || seen !~ /What/ || seen !~ /Why not now/ || seen !~ /Revisit when/) bad = 1 }
    END { if (n) check(); exit (bad || n < 8) }
  ' "$1"
}
check "every idea has a date, a source, what, why not now and when to revisit" every_idea_complete "$IDEAS"
printf '## One\n- Date: 2026-11-17\n- Source: x\n- What: y\n' > "$TMP/idea.md"
refute "an idea without why not now is noticed" every_idea_complete "$TMP/idea.md"

# --- the agent brief keeps parallel agents' scratch files apart
check "the agent brief names scratch files by project" grep -qF '`<project>-<task>-' "$ROOT/templates/agent-brief.md"

# --- the local gate guards main, not every push (D128): it runs before a
# push to main or the merge of a pull request; a push to another branch
# needs only the hook's commit check, so a feature branch may be pushed
# while the test writer's locked tests are still red.
BRIEF="$ROOT/templates/agent-brief.md"
WRITER="$ROOT/templates/test-writer-brief.md"
# gate_before_every_push <file...>: a line runs the gate or the tests
# before every push, other than before every push to main
gate_before_every_push() {
  grep -hiE 'before every push($|[^ ]| [^t]| t[^o])' "$@" | grep -qiE 'gate|tests'
}
refute "no doc runs the gate or the tests before every push" gate_before_every_push "${DOCS[@]}"
printf 'Run them, with the tests, lint, types and build, before every push.\n' > "$TMP/every-push.md"
check "a doc that runs the tests before every push is noticed" gate_before_every_push "$TMP/every-push.md"
# shellcheck disable=SC2016
printf 'Put it in the gate before every push to `main`.\n' > "$TMP/push-to-main.md"
refute "a gate before every push to main is not" gate_before_every_push "$TMP/push-to-main.md"
refute "the rules no longer run the local gate before every push" grep -qF 'Before every push, run the local gate' "$RULES"
refute "the AGENTS template no longer has the gate before every push" grep -qF 'The local gate before every push' "$AGENTS_T"
refute "the skill no longer has a branch push run the rest of the gate" grep -qF 'it runs the rest of the gate' "$VF"
refute "the agent brief no longer holds a branch push until its gate is green" \
  grep -qF 'once its gate (tests, lint, types, build) is green' "$BRIEF"
refute "the test-writer brief no longer forbids a push because its tests are red" \
  grep -qF 'Do not push: the locked tests' "$WRITER"
# shellcheck disable=SC2016
for f in "$RULES" "$SETUP" "$AGENTS_T" "$VF" "$ROOT/README.md"; do
  check "${f#"$ROOT"/} runs the gate before a push to main or the merge of a pull request" \
    grep -qF 'before a push to `main` or the merge of a pull request' "$f"
done
for f in "$RULES" "$AGENTS_T" "$VF" "$BRIEF" "$WRITER"; do
  check "${f#"$ROOT"/} lets a feature branch be pushed while its locked tests are red" \
    grep -qF 'locked tests are red' "$f"
done
# A branch push needing no gate never lets an implementer report red work
# as done.
check "the agent brief still runs Verify before work is reported done" grep -qF 'before you report it done' "$BRIEF"
for f in "$SETUP" "$VF"; do
  check "${f#"$ROOT"/} names D128" grep -qF 'D128' "$f"
done
check "docs/decisions.md records D128, amending D39 and D114" \
  grep -qE '^\| D128 \|.*D39.*D114' "$ROOT/docs/decisions.md"

# --- a showcase project merges on GitHub, where no local hook runs: a
# required CI check runs the feature checks and the walkthrough check on
# its pull requests, set up before its first feature pull request merges;
# until then the coordinator runs both by hand before the merge (D129).
check "the setup file has a showcase project with feature files add the CI job" \
  grep -qF 'A showcase project with feature files adds a CI job' "$SETUP"
# shellcheck disable=SC2016
check "the setup file makes that job a required check" grep -qF 'a required check in the ruleset on `main`' "$SETUP"
for f in "$SETUP" "$VF" "$AGENTS_T" "$ROOT/README.md"; do
  check "${f#"$ROOT"/} names D129" grep -qF 'D129' "$f"
done
# The by-hand run uses the hook's real interface: check-walkthrough
# [<commit>], installed next to pre-push.
check "the walkthrough hook takes a commit" grep -qxF '# Usage: check-walkthrough [<commit>]' "$ROOT/hooks/check-walkthrough"
check "the skill runs the walkthrough check by hand before a showcase merge" \
  grep -qF 'bash .githooks/check-walkthrough HEAD' "$VF"
# shellcheck disable=SC2016
check "the skill merges only the commit it checked" grep -qF -- '--match-head-commit "$(git rev-parse HEAD)"' "$VF"
check "the skill says a merge on GitHub runs no local hook" grep -qF 'runs no local hook' "$VF"
check "docs/decisions.md records D129, after D128" \
  grep -qE '^\| D129 \|.*required check' "$ROOT/docs/decisions.md"

finish
