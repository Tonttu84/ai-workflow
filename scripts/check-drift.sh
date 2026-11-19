#!/usr/bin/env bash
# Reports how a project migrated to the ai-workflow rules has drifted
# from this ai-workflow clone, the one this script lives in, as checked
# out (D153). It never fetches and never writes. Four kinds of drift:
#
#   1. exact copies that differ from the clone: the hooks of
#      hooks/install.sh (in .githooks/, or with --git-hooks in the
#      clone's own hooks folder) and the gate scripts of --gate (in
#      .ai-workflow/), with the install.sh command that replaces them;
#      and hooks in .githooks/ that do not run, since core.hooksPath is
#      not set in this clone of the project;
#   2. templates changed here since the project copied them, with the
#      template's own change since then, never the project's edits. The
#      commit comes from the project's .ai-workflow-copies, which
#      install.sh and scripts/copy-template.sh write; for a copy it does
#      not list (commit-check.yml, feature-check.yml, dependabot.yml,
#      gate.conf and commitlint.config.mjs at their usual paths), from
#      the version in the template's history closest to the copy, and the
#      report says it guessed;
#   3. required files that are missing: a committed gate.conf (D142),
#      and where .claude/ exists, a committed .gitignore that ignores
#      .claude/worktrees/ and .claude/settings.local.json (D151);
#   4. upgrade notes (docs/upgrading.md) added after the commit of the
#      record's notes line; with no notes line, every note, flagged as
#      unknown.
# It also reports the clone's own state, from local refs only: a branch
# behind its upstream, with no upstream or other than the default, no
# branch at all, uncommitted changes in what it compares, and a clone
# older than the record. A record line that is not a full commit SHA and
# two plain relative paths (or "notes" and a full SHA) is reported as
# not valid and ignored, never handed to git. A git call that fails is
# a line of the report too. Each of these counts as drift.
#
# Usage: check-drift.sh [--session] [project-dir]
#
#   project-dir  any folder in the project (default .). A migrated project
#                has an AGENTS.md that names Tonttu84/ai-workflow, a hook
#                of ours or a .ai-workflow-copies; this clone and its
#                worktrees are not projects.
#   --session    for a Claude Code SessionStart hook (D154): reads the
#                hook's JSON on stdin and checks the folder its cwd names.
#                Prints nothing outside a git repository, in a project
#                that is not migrated, in this clone, or when there is no
#                drift; else a short report, under 3,000 characters, that
#                ends with the command for the full one. Always exits 0.
#                It stops after CHECK_DRIFT_DEADLINE seconds (default 8)
#                and says so.
#
# Exit status: 0 no drift, 1 drift, 2 bad usage (an unknown option, a
# folder that is not in a migrated project's git repository, this clone
# itself, or a clone that is not a git repository).
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
templates/gate.conf gate.conf
templates/commitlint.config.mjs commitlint.config.mjs"
# What a record line may hold: a full commit SHA, and relative paths of
# plain characters (D164).
SHA_RE='^([0-9a-f]{40}|[0-9a-f]{64})$'
PATH_RE='^[A-Za-z0-9._@+-]+(/[A-Za-z0-9._@+-]+)*$'
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
valid_sha() {
  local LC_ALL=C
  [[ $1 =~ $SHA_RE ]]
}
# valid_path <path>: relative, plain characters, no component that is
# . or .. or starts with -
valid_path() {
  local LC_ALL=C
  [[ $1 =~ $PATH_RE ]] || return 1
  case /$1/ in */./* | */../* | */-*) return 1 ;; esac
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
# common_dir <dir>: the git common dir of the repository there, absolute
common_dir() { (cd "$1" && cd "$(git rev-parse --git-common-dir 2> /dev/null)" && pwd -P); }

# migrated <top>: the project follows the rules: its AGENTS.md names
# them, or it has a record or a hook of ours
migrated() {
  [ -f "$1/$RECORD" ] && return 0
  grep -qF 'Tonttu84/ai-workflow' "$1/AGENTS.md" 2> /dev/null && return 0
  has_ours "$1/.githooks" && return 0
  has_ours "$(hooks_dir "$1")"
}
# the_clone <top>: the repository is this clone or one of its worktrees
the_clone() {
  local a b
  a=$(common_dir "$1") && b=$(common_dir "$clone") && [ "$a" = "$b" ]
}
# ai_workflow_repo <top>: the repository is an ai-workflow clone of its
# own, by what its top holds: hooks/install.sh and scripts/check-drift.sh,
# with hooks/commit-msg and hooks/pre-push carrying our Source line. A
# project installs our hooks in .githooks/, never in hooks/ (D169).
ai_workflow_repo() {
  [ -f "$1/hooks/install.sh" ] && [ -f "$1/scripts/check-drift.sh" ] &&
    ours "$1/hooks/commit-msg" && ours "$1/hooks/pre-push"
}

# Each check adds its findings to the full report and the short one;
# a git call that fails, and the clone's own state, have lists of their
# own, shown first.
full='' brief='' fails='' about_clone='' drift=0
brief_only=0 # 1 in --session, which leaves the diffs to the full report
say() { full="$full$1"$'\n'; }
tell() { brief="$brief$1"$'\n'; }
# could_not <what> <git subcommand>: a check that could not run
could_not() {
  drift=1
  fails="${fails}could not check $1: git $2 failed."$'\n'
}
# clone_line <text>: something about the clone that makes the comparison
# unreliable
clone_line() {
  drift=1
  about_clone="$about_clone$1"$'\n'
}

# read_record: $rec_notes, the notes commit, and $rec_entries, one
# "<commit>\t<path here>\t<path in the project>" line per copy. A line
# that is not valid is reported by its number, never shown.
NOTES_LINE_RE='^notes ([^ ]+)$'
COPY_LINE_RE='^([^ ]+) ([^ ]+) ([^ ]+)$'
read_record() {
  local line n=0 bad='' c there here
  has_record=0 rec_notes='' rec_entries=''
  [ -f "$top/$RECORD" ] || return 0
  has_record=1
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    line=${line%$'\r'}
    case $line in '' | '#'*) continue ;; esac
    if [[ $line =~ $NOTES_LINE_RE ]]; then
      c=${BASH_REMATCH[1]}
      if valid_sha "$c"; then
        rec_notes=$c
        continue
      fi
    elif [[ $line =~ $COPY_LINE_RE ]]; then
      c=${BASH_REMATCH[1]} there=${BASH_REMATCH[2]} here=${BASH_REMATCH[3]}
      case $there in hooks/* | scripts/* | templates/*) ;; *) there= ;; esac
      if [ -n "$there" ] && valid_sha "$c" && valid_path "$there" && valid_path "$here"; then
        rec_entries="$rec_entries$c$TAB$there$TAB$here"$'\n'
        continue
      fi
    fi
    bad="$bad $n"
  done < "$top/$RECORD"
  [ -n "$bad" ] || return 0
  drift=1
  say "The record, $RECORD, has lines the check ignores (a record line is a full commit SHA and"
  say "two plain relative paths, or \"notes\" and a full SHA; the install and the template helper"
  say "write it):"
  for n in $bad; do
    say "  line $n is not valid"
    tell "- Line $n of $RECORD is not valid; the check ignores it."
  done
  say ""
}
# record_has <prefix>: the record lists a copy whose path starts so
record_has() { printf '%s' "$rec_entries" | awk -F '\t' -v p="$1" 'index($3, p) == 1 { f = 1 } END { exit !f }'; }

# check_clone: the clone's branch, its upstream and its uncommitted
# changes, from local refs only
check_clone() {
  local branch status upstream behind remote=origin default changed
  branch=$(git -C "$clone" symbolic-ref -q --short HEAD 2> /dev/null)
  status=$?
  case $status in
    0) ;;
    1) clone_line "The clone is not on a branch (a detached HEAD): check out its default branch." ;;
    *) could_not "the clone's branch" symbolic-ref ;;
  esac
  if [ "$status" -eq 0 ]; then
    if upstream=$(git -C "$clone" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2> /dev/null); then
      remote=${upstream%%/*}
      if behind=$(git -C "$clone" rev-list --count --end-of-options 'HEAD..@{upstream}' 2> /dev/null); then
        [ "$behind" -eq 0 ] ||
          clone_line "The clone is $behind commit(s) behind $upstream as of its last fetch: pull it (git -C $(quote "$clone") pull)."
      else
        could_not "whether the clone is behind" rev-list
      fi
    else
      clone_line "The clone's branch $branch has no upstream, so the check cannot tell whether it is behind: set one (git -C $(quote "$clone") branch -u origin/main)."
    fi
    default=$(git -C "$clone" symbolic-ref -q --short "refs/remotes/$remote/HEAD" 2> /dev/null)
    case $? in
      0) default=${default#"$remote"/} ;;
      1) default=main ;;
      *) could_not "the clone's default branch" symbolic-ref; default=$branch ;;
    esac
    [ "$branch" = "$default" ] ||
      clone_line "The clone is on branch $branch, not the default branch $default: check out $default."
  fi
  if changed=$(git -C "$clone" status --porcelain --untracked-files=no -- hooks scripts templates docs/upgrading.md 2> /dev/null); then
    [ -z "$changed" ] ||
      clone_line "The clone has uncommitted changes in hooks/, scripts/, templates/ or docs/upgrading.md: commit or drop them, since the check takes the templates and notes from its last commit."
  else
    could_not "the clone's uncommitted changes" status
  fi
}

# check_record_commits: each commit the record names is in the history
# of the clone's HEAD; $usable lists those that are. One on no branch of
# the clone came from an ai-workflow branch that was squashed or rebased,
# which no pull brings back (D168).
check_record_commits() {
  local c reachable missing=0 older=0 squashed=0 status branches
  usable=' '
  [ "$has_record" -eq 1 ] || return 0
  if ! reachable=$(git -C "$clone" rev-list HEAD 2> /dev/null); then
    could_not "the record's commits" rev-list
    return
  fi
  for c in $(printf '%s' "$rec_entries" | cut -f 1 | sort -u) $rec_notes; do
    case $usable in *" $c "*) continue ;; esac
    case $'\n'$reachable$'\n' in
      *$'\n'"$c"$'\n'*) usable="$usable$c "; continue ;;
    esac
    git -C "$clone" cat-file -e --end-of-options "$c" 2> /dev/null
    status=$?
    case $status in
      0) ;;
      1) missing=1; continue ;;
      *) could_not "the record's commit ${c:0:7}" cat-file; continue ;;
    esac
    if ! branches=$(git -C "$clone" for-each-ref --format=x --contains="$c" refs/heads refs/remotes 2> /dev/null); then
      could_not "the record's commit ${c:0:7}" for-each-ref
    elif [ -n "$branches" ]; then
      older=1
    else
      squashed=1
    fi
  done
  [ "$missing" -eq 0 ] ||
    clone_line "The clone is older than the record: the record names commits this clone does not have. Pull the clone. If that does not help, they came from an ai-workflow branch that was squashed or rebased: compare the copies by hand, then re-record them with --force."
  [ "$older" -eq 0 ] ||
    clone_line "The clone is older than the record, or on another branch: the record names commits that are not in the history of its HEAD. Pull the clone, or check out its default branch."
  [ "$squashed" -eq 0 ] ||
    clone_line "The record names commits that are on no branch of the clone: they came from an ai-workflow branch that was squashed or rebased, so no pull brings them. Compare the copies by hand, then re-record them with --force: hooks/install.sh --force, scripts/copy-template.sh --force <template> <dest>, --record --force or --notes-followed --force."
}

# compare_dir <dir> <shown as> <source dir> <names>: adds to $found the
# copies there that are missing or differ from the clone's, byte for
# byte: one git hash-object for them all (a cmp each is slow on Windows),
# which must answer with one hash a file
compare_dir() {
  local name hashes line ours_hash i=0
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
  if ! hashes=$(git -C "$clone" hash-object --no-filters -- "${files[@]}" 2> /dev/null) ||
    [ "$(printf '%s\n' "$hashes" | grep -c .)" -ne "${#files[@]}" ]; then
    could_not "the copies in $2" hash-object
    return
  fi
  while IFS= read -r line; do
    if [ $((i % 2)) -eq 0 ]; then
      ours_hash=$line
    elif [ "$line" != "$ours_hash" ]; then
      found+=("$2/${names[$((i / 2))]} differs")
    fi
    i=$((i + 1))
  done <<< "$hashes"
}

# locate_copies: where the project keeps copies of ours: $in_githooks
# (.githooks/), $in_gitdir (the folder git runs hooks from, $eff, when
# that is another), $in_gate (.ai-workflow/)
locate_copies() {
  local name
  in_githooks=0 in_gitdir=0 in_gate=0
  if ! eff=$(hooks_dir "$top"); then
    could_not "where the project's hooks run" rev-parse
    eff=
  fi
  if has_ours "$top/.githooks" || record_has .githooks/; then in_githooks=1; fi
  if [ -n "$eff" ] && ! same_dir "$eff" "$top/.githooks" && { has_ours "$eff" || record_has .git/hooks/; }; then
    in_gitdir=1
  fi
  for name in $GATE; do [ -f "$top/.ai-workflow/$name" ] && in_gate=1; done
  record_has .ai-workflow/ && in_gate=1
}

# check_hooks_active: hooks in .githooks/ run only when the project's own
# core.hooksPath names them; a global or system value does not count,
# since it is not the project's setting and runs other hooks (D167)
check_hooks_active() {
  local hp
  [ "$in_githooks" -eq 1 ] && [ "$in_gitdir" -eq 0 ] || return 0
  hp=$(git -C "$top" config --local --get core.hooksPath 2> /dev/null)
  case $? in
    0 | 1) ;;
    *) could_not "core.hooksPath" config; return ;;
  esac
  [ -z "$hp" ] || return 0
  drift=1
  say "The hooks in .githooks/ are not active in this clone: its core.hooksPath is not set, so no"
  say "commit check and no gate run. Run: git -C $(quote "$top") config core.hooksPath .githooks"
  say ""
  tell "- The hooks in .githooks/ are not active: git -C $(quote "$top") config core.hooksPath .githooks"
}

# reinstall_flags: the install.sh options that put the copies back in the
# mode the project uses
reinstall_flags() {
  local hp flags=''
  hp=$(git -C "$top" config --get core.hooksPath 2> /dev/null) || hp=
  case $hp in '' | /* | [A-Za-z]:*) ;; *) hp="$top/$hp" ;; esac
  if [ "$in_gitdir" -eq 1 ] && [ "$in_githooks" -eq 0 ]; then
    flags=--git-hooks
  elif [ -n "$hp" ] && ! same_dir "$hp" "$top/.githooks"; then
    flags=--copy-only
  fi
  [ "$in_gate" -eq 0 ] || flags="${flags:+$flags }--gate"
  printf '%s' "$flags"
}

# check_copies: the hooks and the gate scripts that differ from the
# clone's, with the command that replaces them, and hooks that do not run
check_copies() {
  local shown hp line joined='' command
  local -a found
  found=()
  locate_copies
  [ "$in_githooks" -eq 0 ] || compare_dir "$top/.githooks" .githooks "$clone/hooks" "$HOOKS"
  if [ "$in_gitdir" -eq 1 ]; then
    case $eff in "$top"/*) shown=${eff#"$top"/} ;; *) shown=$eff ;; esac
    compare_dir "$eff" "$shown" "$clone/hooks" "$HOOKS"
  fi
  if [ "$in_githooks" -eq 0 ] && [ "$in_gitdir" -eq 0 ]; then found+=("no hooks of ours are installed"); fi
  [ "$in_gate" -eq 0 ] || compare_dir "$top/.ai-workflow" .ai-workflow "$clone/scripts" "$GATE"
  check_hooks_active
  [ "${#found[@]}" -gt 0 ] || return 0
  drift=1
  command="bash $(quote "$clone/hooks/install.sh") $(reinstall_flags)"
  command="${command% } $(quote "$top")"
  say "Hooks and gate scripts that differ from the clone's (exact copies):"
  for line in "${found[@]}"; do
    say "  $line"
    joined="${joined:+$joined; }$line"
  done
  hp=$(git -C "$top" config --local --get core.hooksPath 2> /dev/null) || hp=
  if [ -n "$hp" ] && [ "$hp" != .githooks ] && same_dir "$hp" "$top/.githooks"; then
    say "  First: git -C $(quote "$top") config core.hooksPath .githooks (install.sh takes only that"
    say "  value, and this one names the same folder)."
    tell "- First: git -C $(quote "$top") config core.hooksPath .githooks"
  fi
  say "  Reinstall: $command"
  say ""
  tell "- Hooks or gate scripts differ from the clone: $joined."
  tell "  Reinstall: $command"
}

# guess <template> <copy> <commits>: "<commit> <distance>" of the
# template's version closest to the copy, from the commits that changed
# it (newest first): the fewest lines in one and not the other. Each
# version comes from one cat-file --batch, read by byte count; of equally
# close versions the oldest wins, which shows more upstream change
# rather than less. Fails when git does.
guess() (
  set -o pipefail
  printf '%s\n' "$3" | sed "s|\$|:$1|" | git -C "$clone" cat-file --batch 2> /dev/null |
    COPY="$2" COMMITS="$3" LC_ALL=C awk '
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
        else exit 3
      }
    '
)

# compare_template <template> <copy> <commit> <recorded|guessed...>: the
# template's change since that commit, when it has one
compare_template() {
  local t=$1 dest=$2 c=$3 how=$4 stat adds dels merge text
  if ! stat=$(git -C "$clone" diff --numstat --end-of-options "$c" HEAD -- "$t" 2> /dev/null); then
    could_not "$dest" diff
    return
  fi
  [ -n "$stat" ] || return 0
  drift=1
  adds=${stat%%"$TAB"*} dels=${stat#*"$TAB"} dels=${dels%%"$TAB"*}
  merge="bash $(quote "$clone/scripts/copy-template.sh")"
  [ "$how" = recorded ] || merge="$merge --base $c"
  say "  $dest: $t changed upstream since ${c:0:7} ($how), +$adds -$dels lines."
  say "    Merge it, keeping the project's edits: $merge $t $(quote "$dest") $(quote "$top")"
  if [ "$brief_only" -eq 0 ]; then
    if text=$(git -C "$clone" diff --no-color --end-of-options "$c" HEAD -- "$t" 2> /dev/null); then
      say "$(printf '%s\n' "$text" | sed 's/^/      /')"
    else
      could_not "$dest" diff
    fi
  fi
  tell "- $dest: $t changed upstream since ${c:0:7} ($how), +$adds -$dels lines."
}

# check_templates: every template the record lists, then the usual
# copies it does not list, by a guess
check_templates() {
  local saved=$full entries c t dest commits guessed
  full=''
  entries=$(printf '%s' "$rec_entries" | awk -F '\t' 'index($2, "templates/") == 1')
  while IFS=$TAB read -r c t dest; do
    [ -n "$t" ] || continue
    if [ ! -f "$top/$dest" ]; then
      drift=1
      say "  $dest is missing (the record says it came from $t); copy it again or drop it from $RECORD."
      tell "- $dest is missing (copied from $t)."
      continue
    fi
    case $usable in *" $c "*) compare_template "$t" "$dest" "$c" recorded ;; esac
  done <<< "$entries"
  while read -r t dest; do
    [ -f "$top/$dest" ] || continue
    printf '%s' "$rec_entries" | awk -F '\t' -v d="$dest" '$3 == d { f = 1 } END { exit !f }' && continue
    if ! commits=$(git -C "$clone" log --format=%H -- "$t" 2> /dev/null); then
      could_not "$dest" log
      continue
    fi
    [ -n "$commits" ] || continue
    if ! guessed=$(guess "$t" "$top/$dest" "$commits"); then
      could_not "$dest" cat-file
      continue
    fi
    compare_template "$t" "$dest" "${guessed%% *}" "guessed: no record, the closest upstream version"
  done <<< "$GUESSED"
  if [ -n "$full" ]; then
    full="${saved}Templates changed upstream since the project copied them (only the template's own change is shown):"$'\n'"$full"$'\n'
  else
    full=$saved
  fi
}

# not_ignored <path>...: "missing <path>" for each path that no
# committed, unchanged .gitignore ignores (.git/info/exclude and a global
# excludes file do not count, D151), and "failed <git subcommand>" for a
# git call that failed. With HEAD unborn, nothing is committed.
not_ignored() {
  local src pat path status
  if ! git -C "$top" rev-parse -q --verify HEAD > /dev/null 2>&1; then
    printf 'missing %s\n' "$@"
    return
  fi
  # Four fields a path: the rule's source file, its line, the rule, the
  # path; then the status of check-ignore, in a record of its own.
  {
    printf '%s\0' "$@" | git -C "$top" check-ignore -z -v -n --no-index --stdin 2> /dev/null
    printf '\001%s\0\0\0\0' "$?"
  } | while IFS= read -r -d '' src && IFS= read -r -d '' _ && IFS= read -r -d '' pat && IFS= read -r -d '' path; do
    case $src in
      $'\001'*) [ "${src#?}" -le 1 ] || echo "failed check-ignore"; continue ;;
      '' | /* | [A-Za-z]:*) echo "missing $path"; continue ;;
    esac
    if [ "${pat#!}" != "$pat" ]; then echo "missing $path"; continue; fi
    git -C "$top" ls-files --error-unmatch -- "$src" > /dev/null 2>&1
    status=$?
    case $status in
      0) ;;
      1) echo "missing $path"; continue ;;
      *) echo "failed ls-files"; continue ;;
    esac
    git -C "$top" diff --quiet HEAD -- "$src" 2> /dev/null
    status=$?
    case $status in
      0) ;;
      1) echo "missing $path" ;;
      *) echo "failed diff" ;;
    esac
  done
}

# committed <file>: 0 when HEAD holds the file and the index tracks it,
# 1 when not, 2 after reporting a git call that failed
committed() {
  local status listed
  git -C "$top" rev-parse -q --verify HEAD > /dev/null 2>&1 || return 1
  git -C "$top" ls-files --error-unmatch -- "$1" > /dev/null 2>&1
  status=$?
  case $status in 0) ;; 1) return 1 ;; *) could_not "$1" ls-files; return 2 ;; esac
  if ! listed=$(git -C "$top" ls-tree --name-only HEAD -- "$1" 2> /dev/null); then
    could_not "$1" ls-tree
    return 2
  fi
  [ -n "$listed" ]
}

# check_required: a committed gate.conf, and the D151 ignores
check_required() {
  local lines='' line status
  committed gate.conf
  status=$?
  if [ "$status" -eq 1 ]; then
    if [ -f "$top/gate.conf" ]; then
      lines="gate.conf is not committed: a push to main reads it from the commit pushed (D142); commit it."
    else
      lines="gate.conf is missing: a push to main needs it committed (D142). Copy it with: bash $(quote "$clone/scripts/copy-template.sh") templates/gate.conf gate.conf $(quote "$top"), set its command and commit it."
    fi
  fi
  if [ -d "$top/.claude" ]; then
    while IFS= read -r line; do
      case $line in
        "missing "*) lines="$lines${lines:+$'\n'}${line#missing } is not ignored by a committed .gitignore (D151): add it to .gitignore and commit." ;;
        "failed "*) could_not "the D151 ignores" "${line#failed }" ;;
      esac
    done <<< "$(not_ignored .claude/worktrees/ .claude/settings.local.json)"
  fi
  [ -n "$lines" ] || return 0
  drift=1
  say "Required files that are missing:"
  say "$(printf '%s\n' "$lines" | sed 's/^/  /')"
  say ""
  while IFS= read -r line; do tell "- ${line%%:*}."; done <<< "$lines"
}

# notes_lines <commit>: docs/upgrading.md as of HEAD, each line prefixed
# with 1 when a commit after the given one wrote it and 0 when not; with
# no commit, every line with 1. The commit reaches git only through
# rev-list, after --end-of-options: git blame does not honour it.
# Fails, naming the git subcommand, when git does.
notes_lines() {
  local text after
  if [ -z "$1" ]; then
    text=$(git -C "$clone" show HEAD:docs/upgrading.md 2> /dev/null) || { echo show; return 1; }
    printf '%s\n' "$text" | sed 's/^/1 /'
    return 0
  fi
  after=$(git -C "$clone" rev-list --end-of-options "$1..HEAD" 2> /dev/null) || { echo rev-list; return 1; }
  text=$(git -C "$clone" blame --line-porcelain HEAD -- docs/upgrading.md 2> /dev/null) || { echo blame; return 1; }
  printf '%s\n' "$text" | AFTER="$after" awk '
    BEGIN { n = split(ENVIRON["AFTER"], c, "\n"); for (i = 1; i <= n; i++) if (c[i] != "") later[c[i]] = 1 }
    /^[0-9a-f]+ [0-9]+ [0-9]+/ && length($1) >= 40 { new = ($1 in later); next }
    /^\t/ { print new " " substr($0, 2) }
  '
}

# check_notes: the upgrade notes added after the record's notes commit
check_notes() {
  local since=$rec_notes why='' lines listed exists
  if ! exists=$(git -C "$clone" ls-tree --name-only HEAD -- docs/upgrading.md 2> /dev/null); then
    could_not "the upgrade notes" ls-tree
    return
  fi
  [ -n "$exists" ] || return 0
  if [ "$has_record" -eq 0 ]; then
    why="unknown: the project has no $RECORD, so every note is listed"
  elif [ -z "$since" ]; then
    why="unknown: $RECORD has no notes line, so every note is listed"
  else
    case $usable in
      *" $since "*) ;;
      *) why="unknown: the clone does not have the notes commit ${since:0:7} in its history, so every note is listed"; since= ;;
    esac
  fi
  if ! lines=$(notes_lines "$since"); then
    could_not "the upgrade notes" "$lines"
    [ -n "$since" ] || return
    why="unknown: git could not date the notes, so every note is listed"
    since=
    lines=$(notes_lines "") || { could_not "the upgrade notes" "$lines"; return; }
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
  usable=' '
  read_record
  check_clone
  check_record_commits
  check_copies
  check_templates
  check_required
  check_notes
}

head_short() { git -C "$clone" rev-parse --short HEAD 2> /dev/null || echo unknown; }

render_full() {
  printf 'ai-workflow drift check of %s\nagainst the ai-workflow clone at %s, commit %s.\n\n' "$top" "$clone" "$(head_short)"
  if [ "$drift" -eq 0 ]; then
    printf 'No drift: the project matches the clone.\n'
    return
  fi
  [ -z "$fails" ] || printf 'Checks that could not run (each counts as drift):\n%s\n\n' "$(printf '%s' "$fails" | sed 's/^/  /')"
  [ -z "$about_clone" ] || printf 'The ai-workflow clone:\n%s\n\n' "$(printf '%s' "$about_clone" | sed 's/^/  /')"
  printf '%s' "$full"
  printf 'Drift found: see above.\n'
}

# render_brief: the --session report, cut to $LIMIT characters at a line
render_brief() {
  local head tail body cut
  head="ai-workflow drift check: $top differs from the ai-workflow clone ($clone at $(head_short))."
  tail="Full report and commands: bash $(quote "$clone/scripts/check-drift.sh") $(quote "$top")"
  body="$(printf '%s' "$fails$about_clone" | sed 's/^/- /')"
  body="${body:+$body$'\n'}$brief"
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
  the_clone "$top" && return 0
  ai_workflow_repo "$top" && return 0
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
the_clone "$top" && die "$top is the ai-workflow clone, or a worktree of it: it compares projects with itself, so there is nothing to check"
ai_workflow_repo "$top" && die "$top is an ai-workflow repository, another clone of this one: the drift check compares projects, not clones"
migrated "$top" || die "$top is not a migrated project: no AGENTS.md that names Tonttu84/ai-workflow, no hook of ours, no $RECORD"
git -C "$clone" rev-parse -q --verify HEAD > /dev/null 2>&1 || die "the ai-workflow clone at $clone is not a git repository"
collect
render_full
exit "$drift"
