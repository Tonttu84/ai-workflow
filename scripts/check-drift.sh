#!/usr/bin/env bash
# Reports how a project migrated to the ai-workflow rules has drifted
# from this ai-workflow clone, the one this script lives in, as checked
# out (D153). It never fetches and never writes. Four kinds of drift:
#
#   1. exact copies that differ from the clone: the hooks of
#      hooks/install.sh (in .githooks/, or with --git-hooks in the
#      clone's own hooks folder) and the gate scripts of --gate (in
#      .ai-workflow/), with the install.sh command that replaces them;
#   2. templates changed here since the project copied them, with the
#      template's own change since then, never the project's edits. The
#      commit comes from the project's .ai-workflow-copies, which
#      install.sh and scripts/copy-template.sh write; for a copy it does
#      not list (commit-check.yml, feature-check.yml, dependabot.yml and
#      gate.conf at their usual paths), from the version in the
#      template's history closest to the copy, and the report says it
#      guessed;
#   3. required files that are missing: a committed gate.conf (D142),
#      and where .claude/ exists, a committed .gitignore that ignores
#      .claude/worktrees/ and .claude/settings.local.json (D151);
#   4. upgrade notes (docs/upgrading.md) added after the commit of the
#      record's notes line; with no notes line, every note, flagged as
#      unknown.
# It also reports a clone behind its remote-tracking branch, from local
# refs only: the comparison is then out of date.
#
# Usage: check-drift.sh [--session] [project-dir]
#
#   project-dir  any folder in the project (default .). A migrated project
#                has an AGENTS.md that names Tonttu84/ai-workflow, a hook
#                of ours or a .ai-workflow-copies.
#   --session    for a Claude Code SessionStart hook (D154): reads the
#                hook's JSON on stdin and checks the folder its cwd names.
#                Prints nothing outside a git repository, in a project
#                that is not migrated, or when there is no drift; else a
#                short report, under 3,000 characters, that ends with the
#                command for the full one. Always exits 0. It stops after
#                CHECK_DRIFT_DEADLINE seconds (default 8) and says so.
#
# Exit status: 0 no drift, 1 drift, 2 bad usage (an unknown option, a
# folder that is not in a migrated project's git repository, or a clone
# that is not a git repository).
set -u

clone=$(cd "$(dirname "$0")/.." && pwd)
RECORD=.ai-workflow-copies
SOURCE_LINE='^# Source: https://github.com/Tonttu84/ai-workflow'
LIMIT=2900 # the --session report's size, in characters
TAB=$(printf '\t')
# Templates a project copies to these paths, compared by a guess when the
# record does not list them: "<template> <path in the project>".
GUESSED="templates/commit-check.yml .github/workflows/commit-check.yml
templates/feature-check.yml .github/workflows/feature-check.yml
templates/dependabot.yml .github/dependabot.yml
templates/gate.conf gate.conf"
export GIT_OPTIONAL_LOCKS=0 # no index refresh written by a read

usage() { echo "Usage: check-drift.sh [--session] [project-dir]" >&2; exit 2; }
die() { echo "check-drift.sh: $*" >&2; exit 2; }

# The hooks and gate scripts install.sh copies, from its own lists.
list_of() { sed -n "s/^$1=\"\(.*\)\"\$/\1/p" "$clone/hooks/install.sh"; }
HOOKS=$(list_of HOOKS)
GATE=$(list_of GATE)

# quote <word>: the word, single-quoted when the shell needs it
quote() {
  case $1 in
    *[!A-Za-z0-9_./:@=+-]*) printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")" ;;
    *) printf '%s' "$1" ;;
  esac
}

ours() { grep -q "$SOURCE_LINE" "$1" 2> /dev/null; }
# has_ours <dir>: one of the hooks in the folder is ours
has_ours() {
  local name
  for name in $HOOKS; do ours "$1/$name" && return 0; done
  return 1
}
# hooks_dir <top>: the folder git runs the project's hooks from
hooks_dir() {
  local h
  h=$(git -C "$1" rev-parse --git-path hooks 2> /dev/null) || return 1
  case $h in /* | [A-Za-z]:*) ;; *) h="$1/$h" ;; esac
  printf '%s\n' "$h"
}
same_dir() { [ -d "$1" ] && [ -d "$2" ] && [ "$(cd "$1" && pwd -P)" = "$(cd "$2" && pwd -P)" ]; }

# migrated <top>: the project follows the rules: its AGENTS.md names
# them, or it has a record or a hook of ours
migrated() {
  [ -f "$1/$RECORD" ] && return 0
  grep -qF 'Tonttu84/ai-workflow' "$1/AGENTS.md" 2> /dev/null && return 0
  has_ours "$1/.githooks" && return 0
  has_ours "$(hooks_dir "$1")"
}

# read_record: $rec_notes, the notes commit, and $rec_entries, one
# "<commit>\t<path here>\t<path in the project>" line per copy
read_record() {
  has_record=0 rec_notes='' rec_entries=''
  [ -f "$top/$RECORD" ] || return 0
  has_record=1
  rec_notes=$(awk '{ sub(/\r$/, "") } $1 == "notes" && NF == 2 { n = $2 } END { print n }' "$top/$RECORD")
  rec_entries=$(awk '
    { sub(/\r$/, "") }
    /^#/ || NF < 3 || $1 == "notes" { next }
    { d = $0; sub(/^[^ ]+ [^ ]+ /, "", d); print $1 "\t" $2 "\t" d }
  ' "$top/$RECORD")
}
# record_has <prefix>: the record lists a copy whose path starts so
record_has() { printf '%s\n' "$rec_entries" | awk -F '\t' -v p="$1" 'index($3, p) == 1 { f = 1 } END { exit !f }'; }

# Each check adds its findings to the full report and the short one.
full='' brief='' drift=0
brief_only=0 # 1 in --session, which leaves the diffs to the full report
say() { full="$full$1"$'\n'; }
tell() { brief="$brief$1"$'\n'; }

# check_clone: the clone's branch behind its remote-tracking branch
check_clone() {
  local upstream behind
  upstream=$(git -C "$clone" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2> /dev/null) || return 0
  behind=$(git -C "$clone" rev-list --count "HEAD..@{upstream}" 2> /dev/null) || return 0
  [ "$behind" -gt 0 ] || return 0
  drift=1
  say "The ai-workflow clone is $behind commit(s) behind $upstream, as of its last fetch, so this"
  say "report may be out of date: pull it (git -C $(quote "$clone") pull), then check again."
  say ""
  tell "- The clone is $behind commit(s) behind $upstream as of its last fetch: pull it first."
}

# compare_dir <dir> <shown as> <source dir> <names>: adds to $found the
# copies there that are missing or differ from the clone's, byte for
# byte: one git hash-object for them all (a cmp each is slow on Windows)
compare_dir() {
  local name ours_hash theirs_hash
  local -a files names
  files=() names=()
  for name in $4; do
    if [ ! -f "$1/$name" ]; then
      found+=("$2/$name is missing")
    elif [ -f "$3/$name" ]; then
      files+=("$3/$name" "$1/$name")
      names+=("$name")
    fi
  done
  [ "${#names[@]}" -gt 0 ] || return 0
  {
    for name in "${names[@]}"; do
      IFS= read -r ours_hash && IFS= read -r theirs_hash || ours_hash=unreadable
      [ "$ours_hash" = "$theirs_hash" ] || found+=("$2/$name differs")
    done
  } < <(git -C "$clone" hash-object --no-filters -- "${files[@]}" 2> /dev/null)
}

# check_copies: the hooks and the gate scripts, with the command that
# replaces them
check_copies() {
  local gh="$top/.githooks" eff shown in_githooks=0 in_gitdir=0 gate=0 flags='' hp name line joined=''
  local -a found
  found=()
  eff=$(hooks_dir "$top") || eff=
  if has_ours "$gh" || record_has .githooks/; then in_githooks=1; fi
  if [ -n "$eff" ] && ! same_dir "$eff" "$gh" && { has_ours "$eff" || record_has .git/hooks/; }; then
    in_gitdir=1
  fi
  for name in $GATE; do [ -f "$top/.ai-workflow/$name" ] && gate=1; done
  record_has .ai-workflow/ && gate=1
  [ "$in_githooks" -eq 0 ] || compare_dir "$gh" .githooks "$clone/hooks" "$HOOKS"
  if [ "$in_gitdir" -eq 1 ]; then
    case $eff in "$top"/*) shown=${eff#"$top"/} ;; *) shown=$eff ;; esac
    compare_dir "$eff" "$shown" "$clone/hooks" "$HOOKS"
  fi
  if [ "$in_githooks" -eq 0 ] && [ "$in_gitdir" -eq 0 ]; then found+=("no hooks of ours are installed"); fi
  [ "$gate" -eq 0 ] || compare_dir "$top/.ai-workflow" .ai-workflow "$clone/scripts" "$GATE"
  [ "${#found[@]}" -gt 0 ] || return 0
  drift=1
  hp=$(git -C "$top" config --get core.hooksPath 2> /dev/null) || hp=
  case $hp in '' | /* | [A-Za-z]:*) ;; *) hp="$top/$hp" ;; esac
  if [ "$in_gitdir" -eq 1 ] && [ "$in_githooks" -eq 0 ]; then
    flags=--git-hooks
  elif [ -n "$hp" ] && ! same_dir "$hp" "$gh"; then
    flags=--copy-only
  fi
  [ "$gate" -eq 0 ] || flags="${flags:+$flags }--gate"
  say "Hooks and gate scripts that differ from the clone's (exact copies):"
  for line in "${found[@]}"; do
    say "  $line"
    joined="${joined:+$joined; }$line"
  done
  hp=$(git -C "$top" config --local --get core.hooksPath 2> /dev/null) || hp=
  if [ -n "$hp" ] && [ "$hp" != .githooks ] && same_dir "$hp" "$gh"; then
    say "  First: git -C $(quote "$top") config core.hooksPath .githooks (install.sh takes only that"
    say "  value, and this one names the same folder)."
    tell "- First: git -C $(quote "$top") config core.hooksPath .githooks"
  fi
  say "  Reinstall: bash $(quote "$clone/hooks/install.sh") ${flags:+$flags }$(quote "$top")"
  say ""
  tell "- Hooks or gate scripts differ from the clone: $joined."
  tell "  Reinstall: bash $(quote "$clone/hooks/install.sh") ${flags:+$flags }$(quote "$top")"
}

# guess <template> <copy>: "<commit> <distance>" of the template's version
# closest to the copy: the fewest lines in one and not the other. Each
# version's content comes from one cat-file --batch, read by byte count;
# of equally close versions the oldest wins, which shows more upstream
# change rather than less.
guess() {
  local commits
  commits=$(git -C "$clone" log --format=%H -- "$1" 2> /dev/null) || return 1
  [ -n "$commits" ] || return 1
  printf '%s\n' "$commits" | sed "s|\$|:$1|" | git -C "$clone" cat-file --batch 2> /dev/null |
    COPY="$2" COMMITS="$commits" LC_ALL=C awk '
      BEGIN {
        while ((getline line < ENVIRON["COPY"]) > 0) { sub(/\r$/, "", line); want[line]++ }
        n = split(ENVIRON["COMMITS"], commit, "\n")
      }
      function done_version(    d, l, h) {
        d = 0
        for (l in want) { h = (l in have) ? have[l] : 0; d += (want[l] > h) ? want[l] - h : h - want[l] }
        for (l in have) if (!(l in want)) d += have[l]
        dist[i] = d
      }
      state == 0 {
        i++
        if ($2 != "blob") { dist[i] = -1; next }
        size = $3; got = 0; split("", have)
        if (size == 0) { done_version(); state = 2 } else state = 1
        next
      }
      state == 1 {
        got += length($0) + 1
        line = $0; sub(/\r$/, "", line); have[line]++
        if (got >= size) { done_version(); state = (got == size) ? 2 : 0 }
        next
      }
      state == 2 { state = 0; next }
      END {
        for (k = 1; k <= i && k <= n; k++)
          if (dist[k] >= 0 && (best == 0 || dist[k] <= dist[best])) best = k
        if (best) print commit[best], dist[best]
        else exit 1
      }
    '
}

# compare_template <template> <copy> <commit> <recorded|guessed>: the
# template's change since that commit, when it has one
compare_template() {
  local t=$1 dest=$2 c=$3 how=$4 stat adds dels merge
  if ! stat=$(git -C "$clone" diff --numstat "$c" HEAD -- "$t" 2> /dev/null); then
    drift=1
    say "  $dest: its recorded commit ${c:0:7} is not in this clone; pull the clone, or copy it again."
    tell "- $dest: its recorded commit ${c:0:7} is not in this clone."
    return
  fi
  [ -n "$stat" ] || return 0
  drift=1
  adds=${stat%%"$TAB"*} dels=${stat#*"$TAB"} dels=${dels%%"$TAB"*}
  merge="bash $(quote "$clone/scripts/copy-template.sh")"
  [ "$how" = recorded ] || merge="$merge --base ${c:0:12}"
  say "  $dest: $t changed upstream since ${c:0:7} ($how), +$adds -$dels lines."
  say "    Merge it, keeping the project's edits: $merge $t $(quote "$dest") $(quote "$top")"
  [ "$brief_only" -eq 1 ] || say "$(git -C "$clone" diff --no-color "$c" HEAD -- "$t" | sed 's/^/      /')"
  tell "- $dest: $t changed upstream since ${c:0:7} ($how), +$adds -$dels lines."
}

# check_templates: every template the record lists, then the usual
# copies it does not list, by a guess
check_templates() {
  local saved=$full entries c t dest guessed
  full=''
  entries=$(printf '%s\n' "$rec_entries" | awk -F '\t' 'index($2, "templates/") == 1')
  while IFS=$TAB read -r c t dest; do
    [ -n "$t" ] || continue
    if [ ! -f "$top/$dest" ]; then
      drift=1
      say "  $dest is missing (the record says it came from $t); copy it again or drop it from $RECORD."
      tell "- $dest is missing (copied from $t)."
      continue
    fi
    compare_template "$t" "$dest" "$c" recorded
  done <<< "$entries"
  while read -r t dest; do
    [ -f "$top/$dest" ] || continue
    printf '%s\n' "$rec_entries" | awk -F '\t' -v d="$dest" '$3 == d { f = 1 } END { exit !f }' && continue
    guessed=$(guess "$t" "$top/$dest") || continue
    compare_template "$t" "$dest" "${guessed%% *}" "guessed: no record, the closest upstream version"
  done <<< "$GUESSED"
  if [ -n "$full" ]; then
    full="${saved}Templates changed upstream since the project copied them (only the template's own change is shown):"$'\n'"$full"$'\n'
  else
    full=$saved
  fi
}

# not_ignored <path>...: the paths no committed, unchanged .gitignore
# ignores, one per line (.git/info/exclude and a global excludes file do
# not count, D151)
not_ignored() {
  local src pat path
  # Four fields a path: the rule's source file, its line, the rule, the path.
  printf '%s\0' "$@" | git -C "$top" check-ignore -z -v -n --no-index --stdin 2> /dev/null |
    while IFS= read -r -d '' src && IFS= read -r -d '' _ && IFS= read -r -d '' pat && IFS= read -r -d '' path; do
      if [ -n "$src" ] && [ "${pat#!}" = "$pat" ] &&
        git -C "$top" ls-files --error-unmatch -- "$src" > /dev/null 2>&1 &&
        git -C "$top" diff --quiet HEAD -- "$src" 2> /dev/null; then
        continue
      fi
      printf '%s\n' "$path"
    done
}

# check_required: a committed gate.conf, and the D151 ignores
check_required() {
  local lines='' path
  if ! git -C "$top" ls-files --error-unmatch -- gate.conf > /dev/null 2>&1 ||
    ! git -C "$top" cat-file -e HEAD:gate.conf 2> /dev/null; then
    if [ -f "$top/gate.conf" ]; then
      lines="gate.conf is not committed: a push to main reads it from the commit pushed (D142); commit it."
    else
      lines="gate.conf is missing: a push to main needs it committed (D142). Copy it with: bash $(quote "$clone/scripts/copy-template.sh") templates/gate.conf gate.conf $(quote "$top"), set its command and commit it."
    fi
  fi
  if [ -d "$top/.claude" ]; then
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      lines="$lines${lines:+$'\n'}$path is not ignored by a committed .gitignore (D151): add it to .gitignore and commit."
    done <<< "$(not_ignored .claude/worktrees/ .claude/settings.local.json)"
  fi
  [ -n "$lines" ] || return 0
  drift=1
  say "Required files that are missing:"
  say "$(printf '%s\n' "$lines" | sed 's/^/  /')"
  say ""
  while IFS= read -r path; do tell "- ${path%%:*}."; done <<< "$lines"
}

# notes_after <commit>: docs/upgrading.md as of HEAD, each line prefixed
# with 1 when a commit after the given one wrote it and 0 when not; with
# no commit, every line is prefixed with 1. Fails when git blame does.
notes_after() {
  local lines
  if [ -z "$1" ]; then
    git -C "$clone" show HEAD:docs/upgrading.md 2> /dev/null | sed 's/^/1 /'
    return 0
  fi
  lines=$(git -C "$clone" blame --line-porcelain "$1..HEAD" -- docs/upgrading.md 2> /dev/null) || return 1
  printf '%s\n' "$lines" | awk '
    /^[0-9a-f]+ [0-9]+ [0-9]+/ && length($1) >= 40 { new = 1; next }
    /^boundary$/ { new = 0; next }
    /^\t/ { print new " " substr($0, 2) }
  '
}

# check_notes: the upgrade notes added after the record's notes commit
check_notes() {
  local since=$rec_notes why='' lines listed
  if [ "$has_record" -eq 0 ]; then
    why="unknown: the project has no $RECORD, so every note is listed"
    since=
  elif [ -z "$since" ]; then
    why="unknown: $RECORD has no notes line, so every note is listed"
  elif ! git -C "$clone" cat-file -e "$since^{commit}" 2> /dev/null; then
    why="unknown: the notes commit ${since:0:7} in $RECORD is not in this clone (pull it), so every note is listed"
    since=
  fi
  if ! lines=$(notes_after "$since"); then
    why="unknown: git blame could not date the notes after ${since:0:7}, so every note is listed"
    since=
    lines=$(notes_after "")
  fi
  listed=$(printf '%s\n' "$lines" | awk '
    /^[01] ## [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]: / {
      on = ($1 == "1"); line = substr($0, 6); sub(/: /, " ", line)
      if (on) print "H" line
      next
    }
    /^[01] ## / || /^[01] # / { on = 0; next }
    on && NF > 1 { print "B" substr($0, 3) }
  ')
  [ -n "$listed" ] || return 0
  drift=1
  say "Upgrade notes to follow (docs/upgrading.md in the clone)${why:+, $why}:"
  [ -n "$why" ] || say "  (added after ${since:0:7}, the notes commit in $RECORD)"
  say "$(printf '%s\n' "$listed" | sed -e 's/^H/  - /' -e 's/^B/      /')"
  say "  Once they are followed: bash $(quote "$clone/scripts/copy-template.sh") --notes-followed $(quote "$top")"
  say ""
  tell "- Upgrade notes to follow${why:+ ($why)}:"
  tell "$(printf '%s\n' "$listed" | sed -n 's/^H/  - /p')"
}

# collect: every check, in the order of the report
collect() {
  read_record
  check_clone
  check_copies
  check_templates
  check_required
  check_notes
}

head_short() { git -C "$clone" rev-parse --short HEAD 2> /dev/null; }

render_full() {
  printf 'ai-workflow drift check of %s\nagainst the ai-workflow clone at %s, commit %s.\n\n' "$top" "$clone" "$(head_short)"
  if [ "$drift" -eq 0 ]; then
    printf 'No drift: the project matches the clone.\n'
  else
    printf '%s' "$full"
    printf 'Drift found: see above.\n'
  fi
}

# render_brief: the --session report, cut to $LIMIT characters at a line
render_brief() {
  local head tail body cut
  head="ai-workflow drift check: $top differs from the ai-workflow clone ($clone at $(head_short))."
  tail="Full report and commands: bash $(quote "$clone/scripts/check-drift.sh") $(quote "$top")"
  body=$brief
  if [ $((${#head} + ${#body} + ${#tail} + 2)) -gt "$LIMIT" ]; then
    cut="- ... cut here to stay short; the rest is in the full report."
    body=$(printf '%s' "$body" | awk -v max=$((LIMIT - ${#head} - ${#tail} - ${#cut} - 4)) '
      { n += length($0) + 1; if (n > max) exit; print }')
    body="$body"$'\n'"$cut"$'\n'
  fi
  printf '%s\n%s%s\n' "$head" "$body" "$tail"
}

# cwd_of <json>: the string value of the "cwd" key, unescaped; fails
# when there is none, or when it holds an escape a path does not need
cwd_of() {
  printf '%s' "$1" | LC_ALL=C awk '
    { s = s $0 "\n" }
    END {
      p = 0
      while ((i = index(substr(s, p + 1), "\"cwd\"")) > 0) {
        p += i
        if (p > 1 && substr(s, p - 1, 1) == "\\") continue
        rest = substr(s, p + 5)
        sub(/^[ \t\r\n]*:[ \t\r\n]*/, "", rest)
        if (substr(rest, 1, 1) != "\"") exit 1
        out = ""
        for (k = 2; k <= length(rest); k++) {
          ch = substr(rest, k, 1)
          if (ch == "\"") { if (out == "") exit 1; print out; exit 0 }
          if (ch != "\\") { out = out ch; continue }
          k++; ch = substr(rest, k, 1)
          if (ch == "\\" || ch == "\"" || ch == "/") out = out ch
          else exit 1
        }
        exit 1
      }
      exit 1
    }
  '
}

# session_worker <dir>: "top <path>" once the project is known to be a
# migrated one, then the short report when there is drift
session_worker() {
  top=$(git -C "$1" rev-parse --show-toplevel 2> /dev/null) || return 0
  migrated "$top" || return 0
  printf 'top %s\n' "$top"
  brief_only=1
  if [ -z "$HOOKS" ] || [ -z "$GATE" ]; then
    printf 'ai-workflow drift check: cannot read the HOOKS and GATE lists of %s.\n' "$clone/hooks/install.sh"
    return 0
  fi
  if ! git -C "$clone" rev-parse -q --verify HEAD > /dev/null 2>&1; then
    printf 'ai-workflow drift check: the clone at %s is not a git repository, so it cannot check %s.\n' "$clone" "$top"
    return 0
  fi
  collect
  [ "$drift" -eq 0 ] || render_brief
}

# session: the SessionStart hook's run; prints only what the agent needs
session() {
  local json='' dir seconds=${CHECK_DRIFT_DEADLINE:-8} out first last code body
  case $seconds in '' | *[!0-9]* | 0) seconds=8 ;; esac
  IFS= read -r -d '' -t 2 json || true
  dir=$(cwd_of "$json") || return 0
  case $dir in
    [A-Za-z]:\\* | [A-Za-z]:/*)
      if command -v cygpath > /dev/null 2>&1; then dir=$(cygpath -u "$dir"); else dir=$(printf '%s' "$dir" | tr '\134' /); fi ;;
  esac
  [ -d "$dir" ] || return 0
  out=$(
    set -m
    session_worker "$dir" < /dev/null &
    pid=$!
    set +m
    (
      n=0
      while kill -0 "$pid" 2> /dev/null; do
        if [ "$n" -ge "$seconds" ]; then kill -KILL -- "-$pid" 2> /dev/null; exit 0; fi
        sleep 1
        n=$((n + 1))
      done
    ) > /dev/null 2>&1 < /dev/null &
    watchdog=$!
    { wait "$pid"; } 2> /dev/null
    code=$?
    kill "$watchdog" 2> /dev/null
    kill -KILL -- "-$pid" 2> /dev/null
    printf 'exit %s\n' "$code"
  )
  last=${out##*$'\n'}
  code=${last#exit }
  out=${out%"$last"}
  first=${out%%$'\n'*}
  case $first in "top "*) top=${first#top } ;; *) return 0 ;; esac
  body=${out#"$first"$'\n'}
  case $code in
    0) printf '%s' "$body"; return 0 ;;
    137) printf 'ai-workflow drift check: stopped at its %s-second deadline before it finished %s.\n' "$seconds" "$top" ;;
    *) printf 'ai-workflow drift check: failed (status %s) while it checked %s.\n' "$code" "$top" ;;
  esac
  printf 'Run the full check: bash %s %s\n' "$(quote "$clone/scripts/check-drift.sh")" "$(quote "$top")"
}

mode=full
dir=
while [ $# -gt 0 ]; do
  case $1 in
    --session) mode=session ;;
    -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
    --) shift; [ $# -le 1 ] || usage; dir=${1-}; break ;;
    -*) [ "$mode" = session ] && exit 0; usage ;;
    *) [ -z "$dir" ] || usage; dir=$1 ;;
  esac
  shift
done

if [ "$mode" = session ]; then
  if [ -n "$dir" ]; then echo "check-drift.sh: --session takes its folder from the hook's JSON, not an argument" >&2; exit 0; fi
  session
  exit 0
fi

[ -n "$HOOKS" ] && [ -n "$GATE" ] || die "cannot read the HOOKS and GATE lists of $clone/hooks/install.sh"
top=$(git -C "${dir:-.}" rev-parse --show-toplevel 2> /dev/null) || die "${dir:-.} is not in a git repository"
migrated "$top" || die "$top is not a migrated project: no AGENTS.md that names Tonttu84/ai-workflow, no hook of ours, no $RECORD"
git -C "$clone" rev-parse -q --verify HEAD > /dev/null 2>&1 || die "the ai-workflow clone at $clone is not a git repository"
collect
render_full
exit "$drift"
