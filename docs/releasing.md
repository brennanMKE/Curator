# Releasing Curator

Releases are GitHub releases with a notarized DMG attached. The scripts are modelled on Batty's
(`../Batty/scripts/`), without Batty's embedded binaries, beta scheme, Sparkle or website.
Sparkle updates and a download website are planned (PLAN.md, milestone 6).

## Once per Mac: credentials

| Needed | Where | Check |
|---|---|---|
| Developer ID Application certificate and private key | login keychain | `scripts/preflight.sh --credentials-only` |
| App Store Connect API key `AuthKey_DWLP54ACTJ.p8` | `~/.appstoreconnect/`, mode 600 | same |
| `gh` signed in to github.com | `gh auth login` | same |

Curator passes the API key file straight to `notarytool`, so it adds nothing to the Keychain. If
you'd rather use an existing notarytool profile, set `NOTARY_PROFILE` (for example
`NOTARY_PROFILE=Batty-notary`) and the scripts use that instead.

The key and the certificate move between Macs the way Batty's do: see Batty's
`scripts/RELEASE-CREDENTIALS.md`. Treat the `.p8` like a password; App Store Connect won't let
you download it again.

## Each release

1. **Version.** Set `MARKETING_VERSION` in `Config/App.xcconfig` (X.Y.Z). It's the only place
   the version lives; preflight fails if the project file sets one.
2. **Notes.** Add a `## X.Y.Z` section to `CHANGELOG.md`. It becomes the release notes.
3. **Commit** both, on `main`.
4. **Check:** `scripts/preflight.sh`. This is read-only. It checks the tools, the certificate and
   its expiry, that Apple accepts the notary key, `gh`, the version (X.Y.Z, newer than the last
   release, tag free), the changelog section, a clean tree on `main`, and that you're not behind
   `origin/main`.
5. **Build:** `scripts/release.sh`. It runs preflight, then:
   - builds and signs with Developer ID (`make-dmg.sh`), with the build number set to the UTC
     date and time
   - checks the built app has exactly that version and build
   - notarizes (a few minutes; this uploads the DMG to Apple)
   - staples the ticket
   - runs `scripts/verify-dmg.sh`

   The result is `dist/Curator-X.Y.Z.dmg` plus a `.sha256` file.
6. **Tag:** `scripts/tag-release.sh --push`. This creates an annotated `vX.Y.Z` tag and pushes
   `main` and the tag.
7. **Publish:** `scripts/publish-release.sh`. It creates the GitHub release with the DMG and its
   `.sha256` attached, and the changelog section as the notes. Add `--draft` to review it on
   GitHub before it goes public.

Steps 5 to 7 reach outside this Mac (Apple, GitHub), so a person runs them.

## Checking any DMG

```sh
scripts/verify-dmg.sh dist/Curator-X.Y.Z.dmg
```

It checks the stapled ticket, Gatekeeper on the DMG, and a copy with the quarantine flag a
browser download adds. That last one is what people actually hit. Then it mounts the DMG and
checks the app: signature, hardened runtime, Developer ID, secure timestamp, no debugging
entitlement, Gatekeeper, and the Applications link.

## Quick builds for your own Macs

`scripts/make-dmg.sh` makes a Developer ID–signed DMG without notarizing it. That's fine for
your own Macs; copy it with `scp` so macOS doesn't mark it as downloaded.
