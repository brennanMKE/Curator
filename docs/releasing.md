# Releasing Curator

Releases are GitHub releases with a notarized DMG attached. Sparkle updates and a download
website are planned (PLAN.md, milestone 6); until then, this is the whole process.

## Once per Mac: the notary key

Notarization uses the App Store Connect API key `AuthKey_DWLP54ACTJ.p8` (the same key Batty
uses). `scripts/release.sh` passes the key file straight to `notarytool`, so nothing goes in the
Keychain. It expects the file at `~/.appstoreconnect/AuthKey_DWLP54ACTJ.p8`.

The key lives on the MacBook Air. To copy it to another Mac, for example cameron, run this on
the MacBook Air:

```sh
ssh brennan-mac-mini-m4.local 'mkdir -p ~/.appstoreconnect && chmod 700 ~/.appstoreconnect'
scp ~/.appstoreconnect/AuthKey_DWLP54ACTJ.p8 brennan-mac-mini-m4.local:.appstoreconnect/
ssh brennan-mac-mini-m4.local 'chmod 600 ~/.appstoreconnect/AuthKey_DWLP54ACTJ.p8'
```

Treat the `.p8` like a password: it can't be downloaded again from App Store Connect. Batty's
`scripts/RELEASE-CREDENTIALS.md` covers backing it up.

## Each release

1. Set `MARKETING_VERSION` for the `Curator` target (all configurations), then commit.
2. Build, sign, notarize, staple and verify:

   ```sh
   scripts/release.sh
   ```

   This produces `dist/Curator-<version>.dmg`. It refuses to run with uncommitted changes, and
   it checks that Gatekeeper reports `source=Notarized Developer ID` for both the DMG and the app
   inside it.
3. Tag and push:

   ```sh
   git tag -a v<version> -m "Curator <version>"
   git push origin main v<version>
   ```

4. Publish on GitHub:

   ```sh
   gh release create v<version> dist/Curator-<version>.dmg --title "Curator <version>" --notes-file <notes>
   ```

Notarizing uploads the app to Apple, and a release is public, so a person runs these steps.

## Build numbers

`CFBundleVersion` is the UTC date and time of the build (`YYYYMMDDHHMM`, set by
`scripts/make-dmg.sh`), so each build is newer than the last. `MARKETING_VERSION` is the
version people see.
