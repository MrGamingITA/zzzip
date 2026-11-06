#!/bin/bash
# Compila Zzzip in Release e lo installa in /Applications
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate -q
xcodebuild -scheme Zzzip -configuration Release -destination 'platform=macOS' -derivedDataPath build build > build/release.log 2>&1 || { tail -30 build/release.log; exit 1; }
APP=build/Build/Products/Release/Zzzip.app
osascript -e 'tell application "Zzzip" to quit' >/dev/null 2>&1 || true
rm -rf /Applications/Zzzip.app
ditto "$APP" /Applications/Zzzip.app
L=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$L" -u "$APP" 2>/dev/null || true          # keep only the /Applications copy registered
"$L" -f /Applications/Zzzip.app
/System/Library/CoreServices/pbs -update || true
echo "Installed /Applications/Zzzip.app"
