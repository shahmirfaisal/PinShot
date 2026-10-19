#!/bin/bash
# Builds a universal, signed Release of ClipVault and packages it as a DMG.
# Usage: ./scripts/release.sh        → dist/ClipVault-<version>.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="PinShot"
SIGN_ID="ClipVault Developer"

echo "→ Building universal Release…"
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" -configuration Release \
  -destination 'generic/platform=macOS' ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  -derivedDataPath build.noindex clean build > build.log 2>&1 \
  || { echo "✗ Build failed — see build.log"; tail -20 build.log; exit 1; }

APP="build.noindex/Build/Products/Release/${APP_NAME}.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${APP}/Contents/Info.plist")
DMG="dist/${APP_NAME}-${VERSION}.dmg"

echo "→ Checking signature…"
codesign --verify --deep --strict "${APP}"

echo "→ Creating ${DMG}…"
rm -rf dist/staging "${DMG}"
mkdir -p dist/staging
ditto "${APP}" "dist/staging/${APP_NAME}.app"
ln -s /Applications "dist/staging/Applications"
hdiutil create -volname "${APP_NAME}" -srcfolder dist/staging -ov -format UDZO "${DMG}" > /dev/null
rm -rf dist/staging
# The DMG is intentionally left unsigned: a self-signed DMG triggers an extra
# Gatekeeper warning when opened. The app inside is still signed.

echo "✓ Done: ${DMG} ($(du -h "${DMG}" | cut -f1))"
