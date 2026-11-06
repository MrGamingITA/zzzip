#!/bin/bash
# Scarica 7-Zip 26.05 ufficiale (ip7z/7zip) ed estrae solo 7zz + License.txt in Vendor/7zip/
set -euo pipefail
cd "$(dirname "$0")/.."
VER=26.05; TARBALL=7z2605-mac.tar.xz
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
URL="https://github.com/ip7z/7zip/releases/download/$VER/$TARBALL"
curl -fL --retry 3 -o "$TMP/$TARBALL" "$URL"
echo "sha256: $(shasum -a 256 "$TMP/$TARBALL" | cut -d' ' -f1)"
mkdir -p Vendor/7zip
tar -xJf "$TMP/$TARBALL" -C "$TMP" 7zz License.txt
install -m 755 "$TMP/7zz" Vendor/7zip/7zz
install -m 644 "$TMP/License.txt" Vendor/7zip/License.txt
xattr -c Vendor/7zip/7zz || true
echo "OK: $(Vendor/7zip/7zz | head -2 | tail -1)"
