# Releasing Curator

Each release is notarized, published on GitHub with the DMG attached, and published on
[curator.sstools.co](https://curator.sstools.co/) with a signed Sparkle feed entry, so
installed copies update themselves. The scripts are modelled on Batty's (`../Batty/scripts/`),
without Batty's embedded binaries and beta scheme.

## Once per Mac: credentials

| Needed | Where | Used for |
|---|---|---|
| Developer ID Application certificate and private key | login keychain | signing |
| App Store Connect API key `AuthKey_DWLP54ACTJ.p8` | `~/.appstoreconnect/`, mode 600 | notarizing |
| Sparkle EdDSA private key | `~/.sparkle/Curator.key`, mode 600 | signing updates |
| `gh` signed in | `gh auth login` | GitHub releases |
| `CURATOR_WEB_HOST`, `CURATOR_WEB_PATH` | environment | uploading the website |

`scripts/preflight.sh --credentials-only` checks the signing, notary and GitHub rows.

**No Keychain for Curator.** The notary key and the Sparkle key are files, passed straight to
`notarytool` and to Sparkle's `sign_update --ed-key-file`. To use an existing notarytool
profile instead, set `NOTARY_PROFILE` (for example `Batty-notary`).

**The Sparkle key.** `~/.sparkle/Curator.key` holds the base64 of a 32-byte Ed25519 seed,
Sparkle's own export format. Its public half, `SU_PUBLIC_ED_KEY` in `Config/App.xcconfig`, is
compiled into every copy of Curator. **If the private key is lost, installed copies can never
verify another update.** Back it up somewhere safe, apart from this Mac. Preflight checks that
the key file matches the public key the app ships.

Moving credentials between Macs works like Batty's: see Batty's
`scripts/RELEASE-CREDENTIALS.md`. For the Sparkle key, copy `~/.sparkle/Curator.key`.

## Each release

1. **Version:** set `MARKETING_VERSION` in `Config/App.xcconfig` (X.Y.Z). It's the only place
   the version lives.
2. **Notes:** add a `## X.Y.Z` section to `CHANGELOG.md`. It becomes the GitHub release notes,
   Sparkle's update notes, and `changelog.html`.
3. **Commit** both on `main`, then check with `scripts/preflight.sh` (read-only).
4. **Build:** `scripts/release.sh`. It runs preflight, builds and signs with Developer ID,
   checks the version, notarizes, staples and runs `scripts/verify-dmg.sh`. The result is
   `dist/Curator-X.Y.Z.dmg` plus `.sha256`.
5. **Website:** `scripts/update-website.sh`. It copies the DMG to `website/downloads/`, signs it
   and adds its Sparkle item to `appcast.xml`, rebuilds `changelog.html`, and points the
   download button at the new DMG. Commit `website/`.
6. **Tag:** `scripts/tag-release.sh --push` pushes `main` and `vX.Y.Z`.
7. **GitHub:** `scripts/publish-release.sh`, with `--draft` to review first.
8. **Go live:** `scripts/deploy-website.sh`. It uploads the site, and from then on installed
   copies see the update. Use `--dry-run` to check what will change first.

Steps 4 to 8 reach Apple, GitHub and the web host, so a person runs them.

## Checking a DMG

```sh
scripts/verify-dmg.sh dist/Curator-X.Y.Z.dmg
```

It checks the stapled ticket, Gatekeeper on the DMG, and a copy flagged as downloaded. Then it
checks the app inside: signature, hardened runtime, Developer ID, secure timestamp, no debugging
entitlement, Gatekeeper, and the Applications link.

## Quick builds for your own Macs

`scripts/make-dmg.sh` makes a Developer ID–signed DMG without notarizing it. Copy it with `scp`
so macOS doesn't flag it as downloaded.
