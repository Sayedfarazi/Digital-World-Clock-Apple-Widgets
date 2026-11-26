#!/bin/bash
# Builds "Digital World-Clock Widgets.app" (host app + WidgetKit extension) with the Command Line Tools only —
# no Xcode project. Every step Xcode would do is explicit here:
#
#   1. swiftc                  widget extension, host app, helper tools (snapshot/icon renderer, validator)
#   2. bundle                  .app with PlugIns/<widget>.appex, Info.plists from macOS/Resources/*/Info.plist
#   3. App Intents metadata    macOS/scripts/gen_appintents_metadata.py: SPEC checked against Intents.swift before
#                              compiling, then the metadata is written and validated with the system's parser
#   4. icon                    rendered with SwiftUI, packed with iconutil
#   5. codesign                ad-hoc ("Sign to Run Locally"), extension sandboxed via entitlements
#
# usage: macOS/scripts/build.sh [debug|release]       (default: release)
# output: macOS/build/<APP_NAME>.app
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# The code both apps compile (Core, UI, Widget, App) and the city list.
SHARED="$(cd "$ROOT/../Shared" && pwd)"
set -a
# shellcheck source=../config/project.env
source config/project.env
set +a

CONFIGURATION="${1:-release}"
BUILD="$ROOT/build"
SDK="$(xcrun --show-sdk-path)"
TARGET="$ARCH-apple-macos$DEPLOYMENT_TARGET"
case "$CONFIGURATION" in
  release) OPT=(-O) ;;
  debug) OPT=(-Onone -g -D DEBUG) ;;
  *) echo "unknown configuration: $CONFIGURATION" >&2; exit 2 ;;
esac
# swiftc's module cache records its own absolute path. After the project folder moves, every compile fails
# with "was compiled with module cache path …", so start a fresh cache then.
MODULE_CACHE="$BUILD/ModuleCache"
if [ -d "$MODULE_CACHE" ] && [ "$(cat "$MODULE_CACHE/.path" 2>/dev/null)" != "$MODULE_CACHE" ]; then
  rm -rf "$MODULE_CACHE"
fi
mkdir -p "$MODULE_CACHE"
echo "$MODULE_CACHE" > "$MODULE_CACHE/.path"
SWIFTC=(xcrun swiftc -swift-version 5 -target "$TARGET" -sdk "$SDK" "${OPT[@]}" -module-cache-path "$MODULE_CACHE")

APP="$BUILD/$APP_NAME.app"
APPEX="$APP/Contents/PlugIns/$WIDGET_BUNDLE_NAME.appex"
OBJ="$BUILD/obj"
TOOLS="$BUILD/tools"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# Replace $(VAR) in a template with values from macOS/config/project.env.
render_template() {
  python3 - "$1" "$2" <<'PY'
import os, re, sys
src, dst = sys.argv[1:3]
text = open(src, encoding="utf-8").read()   # UTF-8 whatever the locale: the app's copyright has a ©
def value(m):
    key = m.group(1)
    if key not in os.environ:
        sys.exit(f"error: undefined $({key}) in {src}")
    return os.environ[key]
open(dst, "w", encoding="utf-8").write(re.sub(r"\$\((\w+)\)", value, text))
PY
}

mkdir -p "$OBJ" "$TOOLS"

step "Check Intents.swift against the App Intents metadata SPEC"
# Compares the SPEC in gen_appintents_metadata.py with Intents.swift, and writes a Swift file that only
# compiles if parameter types and enum cases match it (compiled into the widget below).
python3 scripts/gen_appintents_metadata.py check "$SHARED/Widget/Intents.swift" "$OBJ/IntentsMatchMetadataSpec.swift"

step "Compile widget extension ($WIDGET_MODULE)"
# Entry point: Foundation's NSExtensionMain, as Xcode links every app extension (-e _NSExtensionMain). It reads
# the launch arguments ExtensionKit passes, then calls our main (the @main WidgetBundle). Starting at main
# directly, the extension traps in _EXRunningExtension at every launch and the gallery never lists the widgets.
"${SWIFTC[@]}" -module-name "$WIDGET_MODULE" -parse-as-library -application-extension \
  "$SHARED"/Core/*.swift "$SHARED"/UI/*.swift "$SHARED"/Widget/*.swift "$OBJ/IntentsMatchMetadataSpec.swift" \
  -Xlinker -e -Xlinker _NSExtensionMain \
  -o "$OBJ/$WIDGET_BUNDLE_NAME"
# grep without -q reads all of nm's output: with -q it can exit early, nm then dies of SIGPIPE, and pipefail
# fails the check even though the symbol is there.
nm -u "$OBJ/$WIDGET_BUNDLE_NAME" | grep -x '_NSExtensionMain' > /dev/null \
  || { echo "error: the widget's entry point must be _NSExtensionMain (see above)" >&2; exit 1; }
nm -g "$OBJ/$WIDGET_BUNDLE_NAME" | grep ' T _main$' > /dev/null \
  || { echo "error: the widget must export _main for NSExtensionMain to call" >&2; exit 1; }

step "Compile host app ($APP_MODULE)"
"${SWIFTC[@]}" -module-name "$APP_MODULE" -parse-as-library \
  "$SHARED"/Core/*.swift "$SHARED"/UI/*.swift "$SHARED"/App/*.swift Sources/App/*.swift \
  -o "$OBJ/$APP_EXECUTABLE"

step "Compile tools"
"${SWIFTC[@]}" -module-name Snapshot "$SHARED"/Core/*.swift "$SHARED"/UI/*.swift Sources/Snapshot/main.swift -o "$TOOLS/Snapshot"
xcrun swiftc -O -module-cache-path "$MODULE_CACHE" scripts/tools/ln_validate.swift -o "$TOOLS/ln_validate"
xcrun swiftc -O -module-cache-path "$MODULE_CACHE" scripts/tools/imgtool.swift -o "$TOOLS/imgtool"

step "App icon"
rm -rf "$BUILD/AppIcon.iconset"
"$TOOLS/Snapshot" --icon "$BUILD/AppIcon.iconset" "$SHARED/Resources/cities.json" > /dev/null
iconutil -c icns -o "$BUILD/AppIcon.icns" "$BUILD/AppIcon.iconset"

step "Assemble $APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APPEX/Contents/MacOS" "$APPEX/Contents/Resources"
cp "$OBJ/$APP_EXECUTABLE" "$APP/Contents/MacOS/"
cp "$OBJ/$WIDGET_BUNDLE_NAME" "$APPEX/Contents/MacOS/"
cp "$SHARED/Resources/cities.json" "$APP/Contents/Resources/"
cp "$SHARED/Resources/cities.json" "$APPEX/Contents/Resources/"
cp "$BUILD/AppIcon.icns" "$APP/Contents/Resources/"
cp "$ROOT/../LICENSE" "$APP/Contents/Resources/LICENSE"
render_template Resources/App/Info.plist "$APP/Contents/Info.plist"
render_template Resources/Widget/Info.plist "$APPEX/Contents/Info.plist"
render_template Resources/Widget/Widget.entitlements "$OBJ/Widget.entitlements"
plutil -convert xml1 "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist" "$OBJ/Widget.entitlements"
plutil -lint "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist" "$OBJ/Widget.entitlements" > /dev/null
printf 'APPL????' > "$APP/Contents/PkgInfo"

step "App Intents metadata"
python3 scripts/gen_appintents_metadata.py "$APPEX/Contents/MacOS/$WIDGET_BUNDLE_NAME" "$WIDGET_MODULE" \
  "$APPEX/Contents/Resources/Metadata.appintents"
python3 scripts/verify_metadata.py "$APPEX" "$TOOLS/ln_validate"

step "Code sign (ad-hoc)"
codesign --force --sign - --timestamp=none --entitlements "$OBJ/Widget.entitlements" "$APPEX"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

step "Done"
echo "$APP"
