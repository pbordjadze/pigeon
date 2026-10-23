#!/usr/bin/env bash
# Fails on compiler warnings in the repository's own sources, read from build logs: the gate that
# keeps new warnings out (main has none). Writes them, once each and relative to the repository,
# to <out> for the report.
#   ci/warnings.sh <out> <build-log>...
# Generated code (.build/, build/) is left out: nothing in the repository can fix it.
set -uo pipefail
OUT="$1"; shift
ROOT="$PWD/"
grep -hF ": warning: " "$@" 2>/dev/null | grep -F "$ROOT" | sed "s#^[^/]*$ROOT##" \
  | grep -vE '^\.?build/' | sort -u > "$OUT"
if [[ -s "$OUT" ]]; then
  echo "$(wc -l < "$OUT" | tr -d ' ') compiler warning(s); fix them (CLAUDE.md › Working here):"
  cat "$OUT"
  exit 1
fi
echo "no compiler warnings"
