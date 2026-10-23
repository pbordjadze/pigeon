#!/usr/bin/env bash
# Runs a Swift toolchain command for the package inside the swift:6.2 Docker image.
#   tools/swift.sh build -c release
#   tools/swift.sh test
# Extra mounts: set PIGEON_MOUNT=/host/dir to expose it at the same path in the container.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if ! docker info >/dev/null 2>&1; then
  (dockerd >/tmp/dockerd.log 2>&1 &)
  for _ in $(seq 1 30); do docker info >/dev/null 2>&1 && break; sleep 1; done
fi
MOUNTS=(-v "$ROOT:$ROOT")
if [[ -n "${PIGEON_MOUNT:-}" ]]; then MOUNTS+=(-v "$PIGEON_MOUNT:$PIGEON_MOUNT"); fi
exec docker run --rm "${MOUNTS[@]}" -w "$ROOT" swift:6.2-noble swift "$@"
