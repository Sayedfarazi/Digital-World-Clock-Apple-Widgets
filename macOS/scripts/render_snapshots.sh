#!/bin/bash
# Renders every widget kind × size × style (and the light/dark, 12/24-hour and monochrome variants) to PNG
# files with the real SwiftUI views — no install, no desktop needed. Use it for visual QA after any UI change.
#
# usage: macOS/scripts/render_snapshots.sh [output-dir]            (default: macOS/build/snapshots)
#        macOS/scripts/render_snapshots.sh --readme [output-dir]   README images (default: docs/images, which
#                                                                  git tracks: run it after a visible change)
#
# Renders into a fresh temporary folder, then publishes with macOS/scripts/tools/publish_snapshots.py, which checks
# every image and replaces only the files of the previous render (listed in world-clock-widgets-snapshots.txt
# in output-dir). Other files there are never touched: a name collision with a file, folder or link it didn't
# write stops the run before anything changes.
#
# Key files:  worldclock-medium-analog.png  — compare with macOS/docs/reference/apple-world-clock-medium-dark.png
#             compare-medium-analog.png     — same, on the desktop "glass" background
#             sheet-digital.png             — every digital variant on one sheet
# --readme:   hero.png, sizes.png, digital-options.png — the widgets on a desktop backdrop, for README.md
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SHARED="$(cd "$ROOT/../Shared" && pwd)"
# shellcheck source=../config/project.env
source config/project.env

MODE=""
DEFAULT_OUT="$ROOT/build/snapshots"
if [ "${1:-}" = "--readme" ]; then
  MODE="--readme"
  DEFAULT_OUT="$(cd "$ROOT/.." && pwd)/docs/images"
  shift
fi
OUT="${1:-$DEFAULT_OUT}"
TOOL="$ROOT/build/tools/Snapshot"
mkdir -p "$ROOT/build/tools"
# swiftc's module cache records its own absolute path. After the project folder moves, every compile fails
# with "was compiled with module cache path …", so start a fresh cache then.
MODULE_CACHE="$ROOT/build/ModuleCache"
if [ -d "$MODULE_CACHE" ] && [ "$(cat "$MODULE_CACHE/.path" 2>/dev/null)" != "$MODULE_CACHE" ]; then
  rm -rf "$MODULE_CACHE"
fi
mkdir -p "$MODULE_CACHE"
echo "$MODULE_CACHE" > "$MODULE_CACHE/.path"

# (Re)build the renderer when it is missing or older than any Core/UI/Snapshot source.
if [ ! -x "$TOOL" ] || [ -n "$(find "$SHARED/Core" "$SHARED/UI" Sources/Snapshot -name '*.swift' -newer "$TOOL" | head -1)" ]; then
  echo "==> Building the snapshot renderer"
  xcrun swiftc -swift-version 5 -O -target "$ARCH-apple-macos$DEPLOYMENT_TARGET" -sdk "$(xcrun --show-sdk-path)" \
    -module-cache-path "$MODULE_CACHE" -module-name Snapshot \
    "$SHARED"/Core/*.swift "$SHARED"/UI/*.swift Sources/Snapshot/main.swift -o "$TOOL"
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/wcw-snapshots.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
"$TOOL" ${MODE:+"$MODE"} "$STAGE" "$SHARED/Resources/cities.json" > /dev/null
python3 scripts/tools/publish_snapshots.py "$STAGE" "$OUT"
