#!/bin/bash
# Publishes a new Zzzip version: bumps the version (also on the website), builds a signed (EdDSA) DMG,
# creates the GitHub release and updates appcast.xml so installed copies update themselves.
#
#   scripts/release.sh 1.1.0 [notes.md]
#
# Needs: clean git tree on main, gh logged in, the Sparkle private key "zzzip" in the login Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
NEW="${1:?usage: scripts/release.sh <version> [release-notes.md]}"
NOTES="${2:-}"
REPO="MrGamingITA/zzzip"
BIN=build/SourcePackages/artifacts/sparkle/Sparkle/bin

[[ "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Version must look like 1.2.3"; exit 1; }
[ "$(git branch --show-current)" = main ] || { echo "Run on main"; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first"; exit 1; }
git rev-parse "v$NEW" >/dev/null 2>&1 && { echo "Tag v$NEW already exists"; exit 1; }

OLD_BUILD=$(sed -n 's/.*CURRENT_PROJECT_VERSION: "\([0-9]*\)".*/\1/p' project.yml)
BUILD=$((OLD_BUILD + 1))
echo "▸ Zzzip $NEW (build $BUILD)"

# 1. bump version, test, build DMG
sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"$NEW\"/; s/CURRENT_PROJECT_VERSION: \"[^\"]*\"/CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml
sed -i '' -E "s/(macOS 14\+ · )v[0-9]+\.[0-9]+\.[0-9]+/\1v$NEW/g" website/index.html
./scripts/test.sh >/dev/null || { echo "Tests failed — nothing published"; git checkout project.yml; exit 1; }
./scripts/make-dmg.sh
DMG="build/dist/Zzzip-$NEW.dmg"

# 2. appcast entry (signed with the Keychain key), pointing at the GitHub release asset
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
cp "$DMG" "$WORK/"
[ -f appcast.xml ] && cp appcast.xml "$WORK/appcast.xml"
[ -n "$NOTES" ] && cp "$NOTES" "$WORK/Zzzip-$NEW.md"
"$BIN/generate_appcast" --account zzzip --embed-release-notes --maximum-versions 10 \
  --download-url-prefix "https://github.com/$REPO/releases/download/v$NEW/" \
  --link "https://github.com/$REPO" -o "$WORK/appcast.xml" "$WORK"
cp "$WORK/appcast.xml" appcast.xml

echo
read -r -p "Publish v$NEW to GitHub now (commit, tag, push, release)? [y/N] " ok
[ "$ok" = y ] || { echo "Stopped. Version bump and appcast.xml are left uncommitted."; exit 0; }

# 3. version commit + release first, appcast last (so clients never see a link that 404s)
git add project.yml website/index.html && git commit -qm "Release $NEW" && git tag "v$NEW"
git push -q origin main "v$NEW"
# "Zzzip.dmg" is a stable name: the website's Download button points to releases/latest/download/Zzzip.dmg
cp "$DMG" build/dist/Zzzip.dmg
NOTE_ARGS=(--generate-notes); [ -n "$NOTES" ] && NOTE_ARGS=(--notes-file "$NOTES")
gh release create "v$NEW" "$DMG" "$DMG.sha256" build/dist/Zzzip.dmg --repo "$REPO" --title "Zzzip $NEW" \
  "${NOTE_ARGS[@]}"
git add appcast.xml && git commit -qm "appcast: $NEW" && git push -q origin main
echo "✓ Published https://github.com/$REPO/releases/tag/v$NEW"
