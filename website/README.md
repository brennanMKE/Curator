# Curator website

The static site at [curator.sstools.co](https://curator.sstools.co/). Like Batty's site, it
has three jobs:

1. The landing page (`index.html`): what Curator is, and the download.
2. The Sparkle update feed (`appcast.xml`). Curator's Release builds check
   `https://curator.sstools.co/appcast.xml`, set in `Config/App.xcconfig`.
3. Release DMGs (`downloads/`). They're kept out of git and are also attached to GitHub
   releases.

There's no build step: plain HTML and one stylesheet. The fonts are Big Shoulders Display and
Source Serif 4, from Google Fonts.

## Files

| File | Edited by |
|---|---|
| `index.html`, `privacy.html`, `css/style.css` | hand. The download button between the `LATEST` markers is rewritten by `scripts/update-website.sh` |
| `appcast.xml` | `scripts/update-website.sh` only |
| `changelog.html` | generated from `CHANGELOG.md` using `src/changelog.template.html` |
| `assets/curator-icon.png`, `apple-touch-icon.png`, `favicon-32.png` | resized from the built app's `AppIcon.icns` |
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

## Deploy

`scripts/deploy-website.sh` rsyncs this folder to the web host. It needs `CURATOR_WEB_HOST`
and `CURATOR_WEB_PATH`. The host also needs a DNS record for `curator.sstools.co` and HTTPS,
set up the same way as Batty's. See `docs/releasing.md`.
