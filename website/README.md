# Curator website

The static site at [curator.sstools.co](https://curator.sstools.co/). Like Batty's site, it
has three jobs:

1. The landing page (`index.html`): what Curator is, and the download.
2. The Sparkle update feed (`appcast.xml`). Curator's Release builds check
   `https://curator.sstools.co/appcast.xml`, set in `Config/App.xcconfig`.
3. Release DMGs (`downloads/`), filled at deploy time from the GitHub releases; never in git.

There's no build step: plain HTML and one stylesheet. The fonts are Big Shoulders Display and
Source Serif 4, from Google Fonts.

## Files

| File | Edited by |
|---|---|
| `index.html`, `privacy.html`, `css/style.css` | hand. The download button between the `LATEST` markers is rewritten by `scripts/update-website.sh` |
| `appcast.xml` | `scripts/update-website.sh` only |
| `changelog.html` | generated from `CHANGELOG.md` using `src/changelog.template.html` |
| `favicon.svg`, `favicon.ico`, `assets/favicon-16.png`, `assets/favicon-32.png` | the browser-tab icon: the robot's hat and head (the menu bar symbol) in Plex gold on charcoal. `favicon.svg` is generated from `Curator/Assets.xcassets/curator.bust.symbolset`; the PNGs are rendered from it with `rsvg-convert`, and `favicon.ico` packs the 16, 32 and 48 px PNGs. Chrome uses the SVG, Safari the ICO/PNGs |
| `assets/curator-icon.png`, `apple-touch-icon.png`, `icon-192.png`, `icon-512.png` | the full app icon, resized from the built app's `AppIcon.icns`, for the page header, iOS home screens and `site.webmanifest` (Chrome) |
| `assets/curator-robot.svg` | the icon's robot in Plex gold, from `Curator/AppIcon.icon/Assets/Curator.svg` |
| `assets/social-card.png` | rendered from `src/social-card.html` (below) |

`src/` and this README aren't uploaded.

## Preview

```sh
cd website && python3 -m http.server 8000     # then open http://localhost:8000/
```

## Re-render the social card

```sh
SHELL_BIN=~/Library/Caches/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-mac-arm64/chrome-headless-shell
$SHELL_BIN --headless --hide-scrollbars --force-prefers-reduced-motion --virtual-time-budget=5000 \
  --window-size=1200,630 --screenshot=website/assets/social-card.png "file://$PWD/website/src/social-card.html"
```

## Deploying (handled by a separate agent)

This repo only prepares `website/`. Each release, `scripts/update-website.sh` updates
`appcast.xml`, `changelog.html` and the download button, and the result is committed. Whoever
deploys the site does this:

1. **Upload `website/`** to the web root for `https://curator.sstools.co/`, leaving out `src/`
   and this `README.md`.
2. **Fill `downloads/` from GitHub releases.** For every
   `<enclosure url="https://curator.sstools.co/downloads/Curator-X.Y.Z.dmg" …>` in
   `appcast.xml`, make sure `downloads/Curator-X.Y.Z.dmg` exists on the server. The file comes
   from `https://github.com/brennanMKE/Curator/releases/download/vX.Y.Z/Curator-X.Y.Z.dmg`,
   with `Curator-X.Y.Z.dmg.sha256` beside it to check against.
3. **Use the file as downloaded.** The appcast's `length` and `sparkle:edSignature` were
   computed from exactly that file. Don't re-compress, rename or re-sign it. A quick check is
   that the file size equals the enclosure's `length`.
4. **Never delete older DMGs** from `downloads/`. Installed copies and old links may still
   point at them.
5. **Don't cache `appcast.xml` for long.** Sparkle reads it to find updates, so a stale copy
   delays them.

A release is only complete on GitHub before it's deployed: the DMG must exist there first.
The DMGs never go in git: `website/downloads/*.dmg` is ignored, and the folder holds only a
`.gitkeep`.
