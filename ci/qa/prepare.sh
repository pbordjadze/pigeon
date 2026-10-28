#!/usr/bin/env bash
# Pigeon's preparation for QA explore, after the install and before the first launch.
#   ci/qa/prepare.sh <udid>
# The simulator stands still at a public place, Boston Common, where the demo drive's made-up
# route is (the car is stopped, so nothing is locked; no real person's places).
set -euo pipefail
xcrun simctl location "$1" set 42.3551,-71.0656
echo "location: Boston Common, standing still"
