#!/bin/zsh
# Builds a Developer ID-signed Curator.app and packages it in a drag-to-Applications
# DMG for installing on your own Macs.
#
# NOT notarized. Notarization needs the notarytool keychain profile (see Batty's
# scripts/RELEASE-CREDENTIALS.md) and uploads the app to Apple, so it's left for a
# person to run. A non-notarized app is fine on your own Macs; see "Installing" below.
#
# Signing: archive with the project's settings (Apple Development, Automatic), then
# export re-signed with Developer ID using *manual* style, so nothing contacts the
# developer portal. Never add -allowProvisioningUpdates here.
#
# Installing on another Mac: copy the DMG with scp/rsync/a file share (these don't add
# the quarantine flag), or if it arrived by AirDrop/browser, open it once via
# System Settings > Privacy & Security > Open Anyway.

set -euo pipefail

# --- CONFIG ------------------------------------------------------------------
APP_NAME="Curator"
SCHEME="Curator"
TEAM_ID="XV8BAAVZ6V"
SIGN_IDENTITY="Developer ID Application: Brennan Stehling (XV8BAAVZ6V)"
# -----------------------------------------------------------------------------

REPO_ROOT="${0:A:h:h}"
BUILD_DIR="$REPO_ROOT/build/dmg"
DIST_DIR="$REPO_ROOT/dist"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
STAGING="$BUILD_DIR/staging"

if ! security find-identity -p codesigning -v | grep -qF "$SIGN_IDENTITY"; then
    print -u2 "error: signing identity not found: $SIGN_IDENTITY"
    exit 1
fi

# Build number = today's UTC date and time, so every package is newer than the last.
BUILD_NUMBER="$(date -u +%Y%m%d%H%M)"
GIT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || print unknown)"

print "==> Cleaning $BUILD_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR" "$STAGING"

cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
PLIST

print "==> Archiving Release (build $BUILD_NUMBER, $GIT_SHA)"
xcodebuild archive \
    -project "$REPO_ROOT/$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=macOS' \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    -quiet

print "==> Exporting with Developer ID"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -quiet

APP_PATH="$EXPORT_DIR/$APP_NAME.app"
[[ -d "$APP_PATH" ]] || { print -u2 "error: exported app not found at $APP_PATH"; exit 1; }

print "==> Verifying app signature"
codesign --verify --deep --strict "$APP_PATH"
codesign -dvv "$APP_PATH" 2>&1 | grep -E "^(Authority|TeamIdentifier|Timestamp|CodeDirectory)" | sed 's/^/    /'

# Name the DMG after its volume while building; macOS can rename a DMG whose
# filename and volume name differ. Rename once at the end.
WORK_DMG="$DIST_DIR/$APP_NAME.dmg"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION-$GIT_SHA.dmg"

print "==> Creating DMG"
ditto "$APP_PATH" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$WORK_DMG" "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$WORK_DMG" -quiet

print "==> Signing DMG"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$WORK_DMG"
codesign --verify --strict "$WORK_DMG"

mv "$WORK_DMG" "$DMG_PATH"
rm -rf "$BUILD_DIR"

print "==> Done: $DMG_PATH"
print "    Version $VERSION (build $BUILD_NUMBER). Signed with Developer ID, not notarized."
