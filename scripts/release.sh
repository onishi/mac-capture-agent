#!/bin/zsh
# Builds a notarized, stapled DMG for Developer ID distribution (D-6).
#
# Requirements (on a Mac with Xcode 16 or later):
#   TEAM_ID         Apple Developer team ID (10 characters)
#   NOTARY_PROFILE  keychain profile created once with:
#                   xcrun notarytool store-credentials <profile> --apple-id <id> --team-id <team>
#
# Usage: TEAM_ID=ABCDE12345 NOTARY_PROFILE=ambient ./scripts/release.sh
set -euo pipefail

: "${TEAM_ID:?Set TEAM_ID to your Apple Developer team ID}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCHEME="AmbientScreenIntelligence"
APP_NAME="AmbientScreenIntelligence"
BUILD="$ROOT/build/release"
ARCHIVE="$BUILD/$APP_NAME.xcarchive"
EXPORT="$BUILD/export"

rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "▸ Testing"
(cd "$ROOT" && swift test)

echo "▸ Archiving"
xcodebuild -project "$ROOT/AmbientScreenIntelligence.xcodeproj" \
  -scheme "$SCHEME" -configuration Release \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_IDENTITY="Developer ID Application" CODE_SIGN_STYLE=Manual \
  archive

echo "▸ Exporting (Developer ID)"
OPTIONS="$BUILD/ExportOptions.plist"
cp "$ROOT/Config/ExportOptions.plist" "$OPTIONS"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$OPTIONS"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" -exportOptionsPlist "$OPTIONS"

APP="$EXPORT/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="$BUILD/$APP_NAME-$VERSION.dmg"

echo "▸ Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "▸ Building DMG"
STAGING="$BUILD/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Ambient Screen Intelligence" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
codesign --sign "Developer ID Application" --timestamp "$DMG"

echo "▸ Notarizing (this can take a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "▸ Stapling"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

echo "✓ $DMG"
