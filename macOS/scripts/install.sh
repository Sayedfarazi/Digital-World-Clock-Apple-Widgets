#!/bin/bash
# Installs macOS/build/<APP_NAME>.app into ~/Applications and registers it (and its widget extension)
# with LaunchServices / PlugInKit so the widgets appear in the widget gallery, then launches the app once:
# chronod (the widget daemon) can withhold an app's widgets from the gallery until the app has been launched.
#
# usage: macOS/scripts/install.sh [--no-launch]      (run macOS/scripts/build.sh first)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../config/project.env
source "$ROOT/config/project.env"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
BUILT="$ROOT/build/$APP_NAME.app"
DEST="$INSTALL_DIR/$APP_NAME.app"

[ -d "$BUILT" ] || { echo "error: $BUILT not found — run scripts/build.sh first" >&2; exit 1; }

# Keep Spotlight/LaunchServices from registering the build copy as a second instance of the app
# (two registered copies of one extension confuse PlugInKit about which binary to run). On macOS 27 Spotlight
# indexes macOS/build despite .metadata_never_index, and a lookup during the install can register the build
# copy with LaunchServices again: launch-disabled, and without its extension. That's harmless as long as
# `pluginkit -m` lists one plug-in, in ~/Applications (seen 2026-11-23).
touch "$ROOT/build/.metadata_never_index"
"$LSREGISTER" -u "$BUILT" 2>/dev/null || true
pluginkit -r "$BUILT/Contents/PlugIns/$WIDGET_BUNDLE_NAME.appex" 2>/dev/null || true

echo "==> Quit running copies"
pkill -x "$APP_EXECUTABLE" 2>/dev/null || true
pkill -x "$WIDGET_BUNDLE_NAME" 2>/dev/null || true

echo "==> Install to $DEST"
mkdir -p "$INSTALL_DIR"
rm -rf "$DEST"
ditto "$BUILT" "$DEST"
xattr -cr "$DEST" 2>/dev/null || true

echo "==> Register"
"$LSREGISTER" -f -R -trusted "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/$WIDGET_BUNDLE_NAME.appex"

# A copy under the app's former name (config/project.env) has the same bundle IDs. Remove it only now that the
# renamed copy is registered: PlugInKit then never holds two copies of the extension for long, and the
# extension never disappears, which would take the placed widgets off the desktop.
if [ -n "${FORMER_APP_NAME:-}" ]; then
  FORMER="$INSTALL_DIR/$FORMER_APP_NAME.app"
  if [ -d "$FORMER" ] && [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$FORMER/Contents/Info.plist" 2>/dev/null)" = "$APP_BUNDLE_ID" ]; then
    echo "==> Remove the copy under the former name: $FORMER"
    pluginkit -r "$FORMER/Contents/PlugIns/$WIDGET_BUNDLE_NAME.appex" 2>/dev/null || true
    "$LSREGISTER" -u "$FORMER" 2>/dev/null || true
    rm -rf "$FORMER"
    # Moving to a new path makes linkd drop the app's App Intents metadata and add it again ("Bundle relocated",
    # about a second). Widget reloads in that gap fail ("Failed to create LinkAction"), and chronod then waits an
    # hour before trying again. Installing once more, after linkd is done, reloads every placed widget.
    if [ ! -e "$FORMER" ]; then
      echo "==> Install once more in 5 seconds, so the placed widgets reload"
      sleep 5
      exec "$0" "$@"
    fi
    echo "warning: couldn't remove $FORMER" >&2
  fi
fi

echo "==> PlugInKit sees:"
sleep 1
pluginkit -m -v -i "$WIDGET_BUNDLE_ID" || true

if [ "${1:-}" != "--no-launch" ]; then
  echo "==> Launch once (opens the settings window)"
  open "$DEST"
fi
echo
echo "Installed. Add widgets: right-click the desktop › Edit Widgets… › search “${APP_NAME}”."
