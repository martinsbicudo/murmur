#!/usr/bin/env bash
# Replaces /Applications/Murmur.app with the fresh build and relaunches it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/build/Murmur.app"
DEST="${INSTALL_DIR:-/Applications}/Murmur.app"

[[ -d "$SRC" ]] || { echo "no build found; run 'make build' first" >&2; exit 1; }

if pgrep -x Murmur >/dev/null; then
  osascript -e 'tell application id "local.murmur.app" to quit' >/dev/null 2>&1 || true
  for _ in {1..20}; do pgrep -x Murmur >/dev/null || break; sleep 0.25; done
  pgrep -x Murmur >/dev/null && { echo "Murmur is still running (recording or processing?). Quit it from the menu bar first." >&2; exit 1; }
fi

rm -rf "$DEST"
ditto "$SRC" "$DEST"
open "$DEST"
echo "installed $DEST"
