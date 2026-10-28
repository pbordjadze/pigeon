#!/usr/bin/env bash
# Selects Xcode <version> for the job's later steps (DEVELOPER_DIR in $GITHUB_ENV), or fails by
# name on a runner image without it.
#   ci/qa/xcode.sh <version>
set -euo pipefail
VERSION="$1"
DIR="/Applications/Xcode_$VERSION.app/Contents/Developer"
[[ -d "$DIR" ]] || { echo "::error::Xcode $VERSION is not on this runner ($DIR); installed: $(ls -d /Applications/Xcode*.app 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"; exit 1; }
echo "DEVELOPER_DIR=$DIR" >> "${GITHUB_ENV:-/dev/null}"
DEVELOPER_DIR="$DIR" xcodebuild -version
