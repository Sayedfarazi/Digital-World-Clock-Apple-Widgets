#!/bin/bash
# Makes the download for a GitHub release: macOS/build/release/Digital-World-Clock-Widgets.zip (APP_NAME with
# hyphens), which holds "Digital World-Clock Widgets.app". People unzip it and move the app to Applications.
# They don't need the Command Line Tools.
#
#   1. build.sh     build and sign the release app
#   2. checks       signature, architecture, version, and no path from this Mac (the home folder) in the app
#   3. zip          ditto, which keeps permissions; no extended attributes or resource forks
#   4. self-test    unzips into macOS/build/release-check, compares the copy with the build file by file
#                   (contents and permissions), verifies its signature, then deletes it
#
# The app is signed ad hoc and isn't notarized (that needs a paid Apple Developer Program membership). On other
# Macs, Gatekeeper blocks a downloaded copy until its quarantine mark is removed, as README.md › Download tells
# people to do:
#   xattr -dr com.apple.quarantine "/Applications/Digital World-Clock Widgets.app"
#
# usage: macOS/scripts/package.sh            (bump MARKETING_VERSION and BUILD_NUMBER in config/project.env first)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../config/project.env
source "$ROOT/config/project.env"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"
APPEX="$APP/Contents/PlugIns/$WIDGET_BUNDLE_NAME.appex"
OUT="$BUILD/release"
ZIP="$OUT/${APP_NAME// /-}.zip"     # Digital-World-Clock-Widgets.zip. README.md names this file
CHECK="$BUILD/release-check"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
fail() { echo "error: $*" >&2; exit 1; }

step "Build the release app"
"$ROOT/scripts/build.sh" release

step "Check the app"
codesign --verify --deep --strict "$APP"
for bin in "$APP/Contents/MacOS/$APP_EXECUTABLE" "$APPEX/Contents/MacOS/$WIDGET_BUNDLE_NAME"; do
  [ "$(lipo -archs "$bin")" = "$ARCH" ] || fail "$bin isn't built for $ARCH only"
done
for plist in "$APP/Contents/Info.plist" "$APPEX/Contents/Info.plist"; do
  version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
  [ "$version" = "$MARKETING_VERSION" ] || fail "$plist says version $version, config/project.env $MARKETING_VERSION"
done
# A path from this Mac, such as a source file's path in an error message, would show the user name to everyone
# who downloads the app.
leaks="$(grep -r -l -a -F "$HOME" "$APP")" && status=0 || status=$?
case $status in
  0) fail "these files contain the path $HOME:"$'\n'"$leaks" ;;
  1) echo "No path from this Mac in the app" ;;
  *) fail "couldn't search the app for $HOME" ;;
esac

step "Zip"
# Spotlight registers the .app bundles it indexes with LaunchServices. A second registered copy of the widget
# extension confuses PlugInKit (install.sh), so keep the unzipped copy below out of the index.
touch "$BUILD/.metadata_never_index"
mkdir -p "$OUT"
rm -f "$ZIP"
ditto -c -k --keepParent --norsrc --noextattr --noacl "$APP" "$ZIP"
! zipinfo -1 "$ZIP" | grep -e '^__MACOSX/' -e '/\._' > /dev/null || fail "the zip holds extended attributes"

step "Unzip and compare with the build"
rm -rf "$CHECK"
mkdir -p "$CHECK"
ditto -x -k "$ZIP" "$CHECK"
COPY="$CHECK/$APP_NAME.app"
modes() { (cd "$1" && find . -exec stat -f '%Lp %N' {} + | sort); }
diff -r "$APP" "$COPY" > /dev/null || fail "the unzipped app differs from the build"
[ "$(modes "$APP")" = "$(modes "$COPY")" ] || fail "file permissions differ after unzipping"
codesign --verify --deep --strict "$COPY"
echo "The unzipped copy matches the build and its signature is valid"
"$LSREGISTER" -u "$COPY" 2>/dev/null || true
pluginkit -r "$COPY/Contents/PlugIns/$WIDGET_BUNDLE_NAME.appex" 2>/dev/null || true
rm -rf "$CHECK"

step "Done"
size="$(du -h "$ZIP" | cut -f1 | tr -d ' ')"
sha="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
cat <<EOF
$ZIP
  $size, version $MARKETING_VERSION (build $BUILD_NUMBER), SHA-256 $sha

Publish it as a GitHub release; README.md links to the latest one. With the GitHub CLI:
  gh release create v$MARKETING_VERSION "$ZIP" --title "$APP_NAME $MARKETING_VERSION"
or on github.com: Releases › Draft a new release › tag v$MARKETING_VERSION › attach the zip › Publish.
EOF
