#!/bin/bash
# Zzzip — build from source and install into /Applications.
# Usage:  git clone https://github.com/MrGamingITA/zzzip.git && cd zzzip && ./scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."

say()  { printf "\033[1;35m▸ %s\033[0m\n" "$*"; }
fail() { printf "\033[1;31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

# 1. macOS 14+
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || fail "Zzzip needs macOS 14 Sonoma or later (you have $(sw_vers -productVersion))."

# 2. Full Xcode (the Command Line Tools alone cannot build apps)
if ! xcodebuild -version >/dev/null 2>&1; then
  fail "Xcode is required. Install it from the App Store (https://apps.apple.com/app/xcode/id497799835), open it once, then run:
     sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  and run this script again."
fi
say "$(xcodebuild -version | head -1) found"

# 3. XcodeGen (generates the Xcode project)
if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    say "Installing XcodeGen with Homebrew…"
    brew install xcodegen
  else
    fail "XcodeGen is required. Install Homebrew (https://brew.sh) and run: brew install xcodegen"
  fi
fi

# 4. 7-Zip engine
if [ ! -x Vendor/7zip/7zz ]; then
  say "Downloading the official 7-Zip 26.05 engine…"
  ./scripts/fetch-7zz.sh
fi

# 5. Build & install
say "Building Zzzip (this takes a minute)…"
mkdir -p build
./scripts/build-and-install.sh

say "Done! Zzzip is in /Applications. Open it and click “Make Zzzip the default app for archives”."
open -a /Applications/Zzzip.app || true
