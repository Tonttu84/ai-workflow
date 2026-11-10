#!/usr/bin/env bash
# Runs every tests/*.test.sh and fails if any of them fails.
set -u
cd "$(dirname "$0")/.." || exit 1

status=0
for t in tests/*.test.sh; do
  bash "$t" || status=1
done

if [ "$status" -eq 0 ]; then echo "all tests passed"; else echo "some tests failed" >&2; fi
exit "$status"
