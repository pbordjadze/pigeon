#!/usr/bin/env bash
# Gathers what a QA explore run leaves in out/: crash reports, the app's log of the run and the
# build's errors.
#   ci/qa/collect.sh <udid> <product> <log subsystem>
set -uo pipefail
UDID="$1" PRODUCT="$2" SUBSYSTEM="$3"
mkdir -p out/crashes
cp ~/Library/Logs/DiagnosticReports/"$PRODUCT"* out/crashes/ 2>/dev/null || true
# The app's log of the run, every category of its subsystem.
xcrun simctl spawn "$UDID" log show --last 90m --info --style compact \
  --predicate "subsystem == \"$SUBSYSTEM\"" > out/test-app.log 2>/dev/null || true
grep -hE "error:|FAIL:" out/app-build.log 2>/dev/null | sort -u > out/errors.txt || true
