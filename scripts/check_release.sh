#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export CODEX_WATCH_SCRATCH_PATH="${CODEX_WATCH_SCRATCH_PATH:-${TMPDIR:-/tmp}/codex-watch-swift-build}"
cd "$ROOT_DIR"

"$ROOT_DIR/scripts/check_contracts.sh"
"$ROOT_DIR/scripts/test_release_scripts.sh"
swift build --scratch-path "$CODEX_WATCH_SCRATCH_PATH" \
    -Xswiftc -strict-concurrency=complete -Xswiftc -warn-concurrency -Xswiftc -warnings-as-errors
