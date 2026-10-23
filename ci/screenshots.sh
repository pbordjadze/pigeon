#!/usr/bin/env bash
# Installs the built app on a simulator and captures one screenshot per demo scenario.
#   ci/screenshots.sh <path/to/Pigeon.app> <outdir> <kind> <udid> [scenario...]
# Each scenario is passed to the app as `-demo <scenario>`; the app renders that state
# deterministically and writes tmp/demo-ready in its container once the content is on
# screen (`DemoMode.markReady`); the screenshot follows after a short settle. Without a
# marker it is taken after the scenario's timeout: "<scenario>@<seconds>" (default 8 s).
# Scenarios whose name contains "dark" are captured in dark appearance. Scenarios whose name
# contains "long-text" are launched with `-NSDoubleLocalizedStrings YES`, which doubles the length
# of every localized string (pseudo-localization), to show what long translations would break.
set -euo pipefail
APP="$1"; OUT="$2"; KIND="$3"; UDID="$4"; shift 4
SCENARIOS=("$@")
[[ ${#SCENARIOS[@]} -eq 0 ]] && SCENARIOS=(routes-empty)
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Info.plist")
mkdir -p "$OUT"
exec > >(tee -a "$OUT/${KIND}-steps.log") 2>&1
step() { echo "$(date +%T) $KIND: $*"; }

xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >/dev/null; step booted
xcrun simctl status_bar "$UDID" override --time "9:41" --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP"; step installed
MARKER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)/tmp/demo-ready"
SETTLE=${SETTLE:-2}
appearance=light
# `ls` fails while there are no reports; under pipefail that would end the script.
count_reports() { { ls ~/Library/Logs/DiagnosticReports/Pigeon* 2>/dev/null || true; } | wc -l | tr -d ' '; }
seen_reports=$(count_reports)
for entry in "${SCENARIOS[@]}"; do
  scenario="${entry%@*}"; delay=8
  [[ "$entry" == *@* ]] && delay="${entry#*@}"
  want=light; [[ "$scenario" == *dark* ]] && want=dark
  if [[ "$want" != "$appearance" ]]; then
    xcrun simctl ui "$UDID" appearance "$want" || true
    appearance="$want"
  fi
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  rm -f "$MARKER"
  launch_args=(-demo "$scenario")
  [[ "$scenario" == *long-text* ]] && launch_args+=(-NSDoubleLocalizedStrings YES)
  step "launch $scenario: $(xcrun simctl launch "$UDID" "$BUNDLE_ID" "${launch_args[@]}" 2>&1 | tr '\n' ' ')"
  started=$SECONDS
  while [[ ! -f "$MARKER" && $((SECONDS - started)) -lt $delay ]]; do sleep 0.25; done
  if [[ -f "$MARKER" ]]; then
    step "$scenario ready after $((SECONDS - started)) s"
    sleep "$SETTLE"
  else
    step "$scenario: no ready marker within $delay s"
  fi
  xcrun simctl io "$UDID" screenshot --type=png "$OUT/${KIND}-${scenario}.png" 2>/dev/null
  # A crash leaves a new report in the host's DiagnosticReports (simulator apps are host processes).
  reports=$(count_reports)
  if [[ "$reports" -gt "${seen_reports:-0}" ]]; then
    step "captured $scenario — CRASH: app crashed (see crashes/)"
  else
    step "captured $scenario"
  fi
  seen_reports=$reports
done
# The tests that follow on this simulator start from the light appearance they'd find on a fresh one.
if [[ "$appearance" != light ]]; then xcrun simctl ui "$UDID" appearance light || true; fi
xcrun simctl spawn "$UDID" log show --last 15m --style compact --predicate 'process == "Pigeon"' > "$OUT/${KIND}-app.log" 2>/dev/null || true
