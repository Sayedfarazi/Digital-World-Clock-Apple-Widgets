#!/bin/bash
# Removes the installed app, its widget extension registration and (with --all) its preferences.
#
# usage: macOS/scripts/uninstall.sh [--all]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../config/project.env
source "$ROOT/config/project.env"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
DEST="$INSTALL_DIR/$APP_NAME.app"

pkill -x "$APP_EXECUTABLE" 2>/dev/null || true
pkill -x "$WIDGET_BUNDLE_NAME" 2>/dev/null || true
# The app, and a copy under its former name (config/project.env) if it has the same bundle ID.
for copy in "$DEST" ${FORMER_APP_NAME:+"$INSTALL_DIR/$FORMER_APP_NAME.app"}; do
  [ -d "$copy" ] || continue
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$copy/Contents/Info.plist" 2>/dev/null)" = "$APP_BUNDLE_ID" ] || continue
  pluginkit -r "$copy/Contents/PlugIns/$WIDGET_BUNDLE_NAME.appex" 2>/dev/null || true
  "$LSREGISTER" -u "$copy" 2>/dev/null || true
  rm -rf "$copy"
  echo "Removed $copy"
done
if [ "${1:-}" = "--all" ]; then
  defaults delete "$APP_BUNDLE_ID" 2>/dev/null || true
  rm -rf "$HOME/Library/Containers/$WIDGET_BUNDLE_ID"
  echo "Removed preferences and the widget's sandbox container"
fi
echo "Widgets already on the desktop disappear once the system notices the extension is gone."
