#!/usr/bin/env bash
# Gathers what a simulator job leaves for the CI report in out/: crash reports, the app's log
# of the run, compiler and check errors, the test results and their attachments.
#   ci/collect.sh <udid>
set -uo pipefail
UDID="$1"
mkdir -p out/attachments out/crashes
cp ~/Library/Logs/DiagnosticReports/Pigeon* out/crashes/ 2>/dev/null || true
# The app's log of the run, should a test lose the app: every category of `Log`, so a new one
# comes along.
xcrun simctl spawn "$UDID" log show --last 90m --info --style compact \
  --predicate 'subsystem == "com.pbordjadze.pigeon"' \
  > out/test-app.log 2>/dev/null || true
grep -hE "error:|FAIL:" out/app-build.log out/app-test.log out/release-build.log out/release-check.log out/sidestore-build.log 2>/dev/null \
  | sort -u > out/errors.txt || true
if [ -d build/Tests.xcresult ]; then
  xcrun xcresulttool get test-results summary --path build/Tests.xcresult --compact > out/test-summary.json 2>/dev/null || true
  xcrun xcresulttool get test-results tests --path build/Tests.xcresult --compact > out/test-results.json 2>/dev/null || true
  xcrun xcresulttool export attachments --path build/Tests.xcresult --output-path out/attachments >/dev/null 2>&1 || true
  # Screen recordings are most of a report's bytes and can't be read from one; the PNGs stay.
  find out/attachments \( -name '*.mp4' -o -name '*.mov' \) -delete 2>/dev/null || true
fi
