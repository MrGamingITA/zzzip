#!/bin/bash
# Builds a Release Zzzip.app and packs it into build/dist/Zzzip-<version>.dmg (+ .sha256) for GitHub Releases.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate -q
mkdir -p build
# Optional overrides (used by release.sh / local update tests): VERSION=1.2.0 BUILD=3 scripts/make-dmg.sh
OVERRIDES=()
[ -n "${VERSION:-}" ] && OVERRIDES+=("MARKETING_VERSION=$VERSION")
[ -n "${BUILD:-}" ] && OVERRIDES+=("CURRENT_PROJECT_VERSION=$BUILD")
xcodebuild -scheme Zzzip -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build ${OVERRIDES[@]+"${OVERRIDES[@]}"} build > build/release.log 2>&1 \
  || { tail -30 build/release.log; exit 1; }
APP=build/Build/Products/Release/Zzzip.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$APP/Contents/Info.plist")
# The build directory copy must not register as a second Zzzip in LaunchServices.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP"

STAGE=$(mktemp -d); trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Zzzip.app"
ln -s /Applications "$STAGE/Applications"
mkdir -p build/dist
OUT="build/dist/Zzzip-$VERSION.dmg"
rm -f "$OUT"
hdiutil create -volname "Zzzip $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT" >/dev/null
(cd build/dist && shasum -a 256 "Zzzip-$VERSION.dmg" > "Zzzip-$VERSION.dmg.sha256")
echo "Created $OUT (version $VERSION, build $BUILD)"
cat "build/dist/Zzzip-$VERSION.dmg.sha256"
