#!/bin/sh
# Builds dist/TrainTimer-<version>.dmg (universal, drag-to-Applications).
#
# Without arguments the app is ad-hoc signed: it runs, but Gatekeeper asks downloaders
# to approve it once (see README). With an Apple Developer account, sign and notarize:
#
#   xcrun notarytool store-credentials traintimer   # once: Apple ID + app-specific password
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=traintimer ./scripts/release.sh
set -eu
cd "$(dirname "$0")/.."

APP=build/DerivedData/Build/Products/Release/TrainTimer.app
STAGING=build/dmg

xcodebuild -project TrainTimer.xcodeproj -scheme TrainTimer -configuration Release \
    -destination "generic/platform=macOS" -derivedDataPath build/DerivedData clean build -quiet

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --options runtime --timestamp \
        --entitlements App/TrainTimer.entitlements --sign "$SIGN_IDENTITY" "$APP"
fi
codesign --verify --strict "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="dist/TrainTimer-$VERSION.dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING" dist
ditto "$APP" "$STAGING/TrainTimer.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -quiet -volname "Train Timer" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
fi

echo "Built $DMG"
shasum -a 256 "$DMG"
