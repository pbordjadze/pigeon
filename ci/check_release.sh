#!/usr/bin/env bash
# Checks a built Release app for what a shipped build must (and must not) contain.
#   ci/check_release.sh <path/to/Pigeon.app>
# It carries the privacy manifest, the export-compliance answer and the background modes a drive
# needs (location, and audio for the voice), asks for location only while in use, and has none of
# the Debug-only code (`DemoMode` and its ready marker): those are compiled out by `#if DEBUG`.
set -euo pipefail
APP="$1"
PLIST="$APP/Info.plist"
BINARY="$APP/$(/usr/libexec/PlistBuddy -c "Print CFBundleExecutable" "$PLIST")"
failed=0
fail() { echo "FAIL: $*"; failed=1; }

[[ -f "$APP/PrivacyInfo.xcprivacy" ]] || fail "PrivacyInfo.xcprivacy is not in the app bundle"
plutil -lint "$APP/PrivacyInfo.xcprivacy" || fail "PrivacyInfo.xcprivacy is not a valid plist"
[[ "$(/usr/libexec/PlistBuddy -c "Print ITSAppUsesNonExemptEncryption" "$PLIST")" == "false" ]] \
  || fail "ITSAppUsesNonExemptEncryption is not false"
modes="$(/usr/libexec/PlistBuddy -c "Print UIBackgroundModes" "$PLIST" 2>/dev/null || true)"
for mode in location audio; do
  grep -qw "$mode" <<< "$modes" || fail "UIBackgroundModes lacks $mode"
done
/usr/libexec/PlistBuddy -c "Print NSLocationWhenInUseUsageDescription" "$PLIST" > /dev/null 2>&1 \
  || fail "no NSLocationWhenInUseUsageDescription"
if /usr/libexec/PlistBuddy -c "Print NSLocationAlwaysAndWhenInUseUsageDescription" "$PLIST" > /dev/null 2>&1; then
  fail "the app asks for Always location; a drive needs only While Using"
fi

# Type names survive in the binary as mangled metadata, the marker as a plain string. Stripping
# first drops the debug map, which names every object file whether or not it compiled to anything.
WORK="$(mktemp -d)"
strip -S -x -o "$WORK/binary" "$BINARY"
strings -a "$WORK/binary" > "$WORK/strings.txt"
for symbol in DemoMode demo-ready; do
  if grep -q "$symbol" "$WORK/strings.txt"; then fail "the Release binary contains $symbol"; fi
done
[[ $failed -eq 0 ]] && echo "Release build ok: privacy manifest, background modes, While Using location, no Debug-only code"
exit $failed
