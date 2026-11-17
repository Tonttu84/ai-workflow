#!/usr/bin/env bash
# Prints the lines changed since a base in JavaScript and TypeScript
# source files as the value for StrykerJS's --mutate option, since
# StrykerJS has no diff mode:
#
#   npx stryker run --incremental --mutate "$(stryker-mutate-ranges.sh <base>)"
#
# Usage: stryker-mutate-ranges.sh <base> [path...]
#
# The change is git diff <base> against the working tree (uncommitted
# edits count), plus untracked files, which are mutated whole; a renamed
# file counts as new. Paths limit the files, and the output's paths are
# relative to the current directory, where Stryker runs; files outside it
# are left out.
#
# Source files end in .ts .tsx .mts .cts .js .jsx .mjs or .cjs; left out
# are declaration files (.d.ts), *.test.* and *.spec.* files, and files
# under __tests__, __mocks__, test, tests, e2e or node_modules. A deleted
# line gives no range: there is nothing left there to mutate.
#
# StrykerJS's range syntax, from its configuration docs (mutate, v10.1.1,
# https://stryker-mutator.io/docs/stryker-js/configuration/): postfix a
# file with ":startLine[:startColumn]-endLine[:endColumn]", as in
# "src/app.js:1-11", lines inclusive; a range cannot be combined with a
# glob in one entry. The CLI splits --mutate on commas
# (packages/core/src/stryker-cli.ts: createSplitter(',')), so the output
# is one comma-separated line and a path with a comma is an error.
#
# Exit status: 0 ranges printed, 1 no changed source line (nothing to
# mutate), 2 bad arguments or a path with a comma.
set -eu -o pipefail

usage() { echo "Usage: stryker-mutate-ranges.sh <base> [path...]" >&2; exit 2; }
die() { echo "stryker-mutate-ranges.sh: $*" >&2; exit 2; }
case ${1:-} in
  -h | --help) awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
esac
[ "$#" -ge 1 ] || usage

git() { command git --literal-pathspecs -c core.quotePath=false "$@"; }
git rev-parse --is-inside-work-tree > /dev/null 2>&1 || die "not inside a git work tree"
name=$1
base=$(git rev-parse --verify --quiet "$name^{commit}") || die "unknown commit: $name"
shift

# source <path>: is it a JavaScript or TypeScript source file, not a test?
source_file() {
  case /$1 in
    *.d.ts | *.d.mts | *.d.cts) return 1 ;;
    *.test.* | *.spec.*) return 1 ;;
    */__tests__/* | */__mocks__/* | */test/* | */tests/* | */e2e/* | */node_modules/*) return 1 ;;
    *.ts | *.tsx | *.mts | *.cts | *.js | *.jsx | *.mjs | *.cjs) return 0 ;;
  esac
  return 1
}

entries=$(
  # Bash clears -e in a command substitution, so each pipeline exits on
  # its own failure (pipefail is set): only the last one would be seen.
  # Changed files: "<path><TAB><start>-<end>" per added or changed hunk.
  git diff -U0 --no-renames --no-color --no-ext-diff --relative \
    --src-prefix=a/ --dst-prefix=b/ --diff-filter=AM "$base" -- "$@" |
    awk '
      /^\+\+\+ / { path = substr($0, 7); sub(/\t$/, "", path); next } # "+++ b/<path>"
      /^@@ / {
        split($3, new, ",") # "+<start>[,<count>]"
        start = substr(new[1], 2)
        count = (2 in new) ? new[2] : 1
        if (count > 0) printf "%s\t%d-%d\n", path, start, start + count - 1
      }
    ' || exit 1
  # Untracked files, whole.
  git ls-files -z --others --exclude-standard -- "$@" |
    while IFS= read -r -d '' file; do
      n=$(awk 'END { print NR }' "$file")
      [ "$n" -eq 0 ] || printf '%s\t1-%d\n' "$file" "$n"
    done || exit 1
) || die "git diff failed, or git ls-files did"

out=
while IFS=$(printf '\t') read -r path range; do
  if [ -z "$path" ] || ! source_file "$path"; then continue; fi
  case $path in *,*) die "a path with a comma cannot be passed to --mutate: $path" ;; esac
  out=${out:+$out,}$path:$range
done <<< "$entries"

[ -n "$out" ] || {
  echo "stryker-mutate-ranges.sh: no changed source line since $name: nothing to mutate" >&2
  exit 1
}
printf '%s\n' "$out"
