# Curator

A SwiftUI macOS app for browsing a Plex library. See README.md for features and PLAN.md for
design notes.

## Tests

- **Unit tests**, safe on any Mac:
  `xcodebuild test -project Curator.xcodeproj -scheme Curator -destination 'platform=macOS,arch=arm64' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- **UI tests run only in a Tart VM:** `scripts/run-ui-tests-vm.sh` (commit first; it exports
  HEAD). Never run the `Curator UI Tests` scheme on a host Mac. XCUITest loads into every
  running app and has crashed Batty. The target refuses to build outside a VM. See
  docs/ui-testing-vm.md.
- **Never script the host's UI** (`osascript` / System Events keystrokes or clicks). Input goes
  to whatever app is in front, which may be the user's terminal.

## Code signing

Never pass `-allowProvisioningUpdates`. Never create, revoke or delete certificates or
profiles, and don't change signing settings in the project. Build unsigned
(`CODE_SIGNING_ALLOWED=NO`) unless the user asks for a signed build and is present.
`scripts/make-dmg.sh` signs with Developer ID; notarizing is done by a person.

## Releases

Version lives only in `Config/App.xcconfig`. Release notes come from `CHANGELOG.md`. The flow
is preflight → release (notarizes) → update-website → tag-release --push → publish-release →
deploy-website; see docs/releasing.md. Those steps reach Apple, GitHub and the web host, so run
them only when the user asks. The Sparkle private key is `~/.sparkle/Curator.key`: never print,
move or regenerate it, since installed copies trust only its public half.

## Secrets

Settings and secrets live in `.env` files (the app's own in Application Support; the repo's
git-ignored `.env` for development). Never use the Keychain.
