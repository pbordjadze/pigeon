#!/usr/bin/env bash
# Waits for the CI report of a commit and extracts it.
#   [CI_BRANCH=<pushed-branch>] ci/fetch.sh [<commit-sha>] [<outdir>]   (defaults: HEAD, ./ci-report)
# The report (published by .github/workflows/ci.yml to the ref refs/ci-shots/<branch>, outside
# refs/heads) contains STATUS.md, logs (*.log, long ones trimmed), <job>/errors.txt, test results,
# and screenshots under */shots/*.png.
# Polls every 30 s for up to 180 min (the macOS runners are shared with paint-by-number, so a run
# can queue behind its). Run it in the background and read the report when done.
set -euo pipefail
SHA="${1:-$(git rev-parse HEAD)}"
OUT="${2:-ci-report}"
BRANCH="${CI_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
REF="refs/ci-shots/${BRANCH}"
for _ in $(seq 1 360); do
  if git fetch -q origin "+${REF}:${REF}" 2>/dev/null; then
    if [[ "$(git show "${REF}:COMMIT" 2>/dev/null)" == "$SHA" ]]; then
      rm -rf "$OUT" && mkdir -p "$OUT"
      git archive "${REF}" | tar -x -C "$OUT"
      cat "$OUT/STATUS.md"
      find "$OUT" -name errors.txt -size +0 -exec sh -c 'echo "== $1"; head -60 "$1"' _ {} \;
      find "$OUT" \( -name '*.png' -o -name '*.jpg' \) | sort
      exit 0
    fi
  fi
  sleep 30
done
echo "Timed out waiting for CI report of $SHA on $REF" >&2
exit 1
