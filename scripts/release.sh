#!/bin/zsh
# Builds a notarized Curator DMG for a GitHub release.
#
#   scripts/release.sh            build, sign, notarize, staple, verify -> dist/Curator-<version>.dmg
#
# Tagging, pushing and `gh release create` are separate, deliberate steps (see docs/releasing.md).
# Notarization uploads the DMG to Apple, so a person starts this script.
#
# Notary credentials: the App Store Connect API key file, passed straight to notarytool, so
# nothing is stored in the Keychain. Override with environment variables if needed:
#   ASC_KEY_PATH   default ~/.appstoreconnect/AuthKey_DWLP54ACTJ.p8
#   ASC_KEY_ID     default DWLP54ACTJ
#   ASC_ISSUER     default 69a6de6e-9f19-47e3-e053-5b8c7c11a4d1
# (the same key Batty uses; see Batty's scripts/RELEASE-CREDENTIALS.md for moving it between Macs)

set -euo pipefail

APP_NAME="Curator"
REPO_ROOT="${0:A:h:h}"
DIST_DIR="$REPO_ROOT/dist"
ASC_KEY_ID="${ASC_KEY_ID:-DWLP54ACTJ}"
ASC_ISSUER="${ASC_ISSUER:-69a6de6e-9f19-47e3-e053-5b8c7c11a4d1}"
ASC_KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/AuthKey_$ASC_KEY_ID.p8}"

log()  { print -r -- "==> $*"; }
fail() { print -u2 -r -- "error: $*"; exit 1; }

# --- Preflight ---------------------------------------------------------------

[[ -f "$ASC_KEY_PATH" ]] || fail "App Store Connect key not found at $ASC_KEY_PATH (copy it from the Mac that has it; see docs/releasing.md)"
[[ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]] || fail "working tree has uncommitted changes; release from a clean commit"

VERSION="$(xcodebuild -project "$REPO_ROOT/$APP_NAME.xcodeproj" -target "$APP_NAME" -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F' = ' '/^ +MARKETING_VERSION /{print $2; exit}')"
[[ -n "$VERSION" ]] || fail "couldn't read MARKETING_VERSION"
if git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
    [[ "$(git -C "$REPO_ROOT" rev-list -n1 "v$VERSION")" == "$(git -C "$REPO_ROOT" rev-parse HEAD)" ]] \
        || fail "tag v$VERSION already exists on a different commit; bump MARKETING_VERSION"
fi
log "Releasing $APP_NAME $VERSION from $(git -C "$REPO_ROOT" rev-parse --short HEAD)"

# --- Build and sign (Developer ID) -------------------------------------------

"$REPO_ROOT/scripts/make-dmg.sh"
BUILT="$(ls -t "$DIST_DIR"/$APP_NAME-$VERSION-*.dmg | head -1)"

# Notarize under a name equal to the volume name: macOS can rename a DMG whose file name and
# volume name differ during the notary round trip. Rename to the release name only at the end.
WORK_DMG="$DIST_DIR/$APP_NAME.dmg"
FINAL_DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$WORK_DMG" "$FINAL_DMG"
mv "$BUILT" "$WORK_DMG"

# --- Notarize, staple, verify ------------------------------------------------

log "Submitting to Apple's notary service (this can take a few minutes)"
xcrun notarytool submit "$WORK_DMG" \
    --key "$ASC_KEY_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER" \
    --wait --timeout 30m

log "Stapling the ticket"
xcrun stapler staple "$WORK_DMG"
xcrun stapler validate "$WORK_DMG"

log "Verifying as a downloaded file would be checked"
spctl -a -t open --context context:primary-signature -vv "$WORK_DMG" 2>&1 | tee /dev/stderr | grep -q "source=Notarized Developer ID" \
    || fail "Gatekeeper doesn't accept the DMG as notarized"

MOUNT="$(hdiutil attach -nobrowse -readonly "$WORK_DMG" | awk -F'\t' '/\/Volumes\//{print $NF}')"
trap '[[ -n "${MOUNT:-}" ]] && hdiutil detach "$MOUNT" -quiet || true' EXIT
spctl -a -t exec -vv "$MOUNT/$APP_NAME.app" 2>&1 | tee /dev/stderr | grep -q "source=Notarized Developer ID" \
    || fail "Gatekeeper doesn't accept the app inside the DMG as notarized"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOUNT/$APP_NAME.app/Contents/Info.plist")"
[[ "$BUNDLE_VERSION" == "$VERSION" ]] || fail "app says $BUNDLE_VERSION, expected $VERSION"
hdiutil detach "$MOUNT" -quiet
MOUNT=""

mv "$WORK_DMG" "$FINAL_DMG"
log "Done: $FINAL_DMG"
shasum -a 256 "$FINAL_DMG"
