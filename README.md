# Curator

A native macOS companion to Plex for browsing your library and watching new imports arrive.

Curator connects to a Plex Media Server on your network. It shows what was just added,
searches titles, cast and crew, and tells you exactly which file Plex is playing. It's
built for the moment you're ripping and importing discs and want to see them land.

## Features

- **Recently Added** across all libraries, grouped into Today, Yesterday, Last 7 Days and
  Earlier. It refreshes every minute, badges anything imported in the last 3 hours as
  NEW, and shows a banner when a title arrives.
- **Search** by title, and also by actor or director ("Coen" finds *Fargo* and *The Big
  Lebowski*). Matches on cast or crew say why they matched.
- **Browse** each library in title order.
- **Details inspector** for the selected title: artwork, summary, runtime, cast, when it
  was added, video and audio format, and the file path and size on the server.
- **Menu bar button** listing the last 5 imports and how long ago each arrived, with a
  count of those added in the last 3 hours.
- **Grid or list** view.
- **Keyboard**:

  | Key | Action |
  |---|---|
  | Arrow keys | Move the selection |
  | Return | Open the selected title in Plex Web |
  | Space | Quick Look–style preview |
  | ⌘F | Search |
  | ⌘R | Refresh |

- **Artwork** comes from TMDB when you add an API key, and from Plex otherwise.

## Requirements

- macOS 26 or later
- A Plex Media Server you can reach over HTTP (LAN or Tailscale)
- Optional: a [TMDB API key](https://www.themoviedb.org/settings/api), v3 key or v4 read
  token, for better artwork

## Setup

Curator stores its settings in a `.env` file inside its own container (Application
Support). It never uses the Keychain. The keys match [`.env.example`](.env.example):

| Key | Value |
|---|---|
| `PLEX_URL` | Server address, e.g. `http://my-plex-mac:32400`. A bare name or IP also works; Curator adds port 32400. |
| `PLEX_TOKEN` | Your Plex server token |
| `TMDB_API_KEY` | Optional TMDB key |

Enter them in **Settings** (⌘,). Each field has step-by-step help. To find the Plex
token, open any movie in Plex Web, choose **⋯ → Get Info → View XML**, and copy the
`X-Plex-Token` value from the page's URL. If the server is a Mac, you can also run this
on it:

```sh
defaults read com.plexapp.plexmediaserver PlexOnlineToken
```

The repo's own `.env` (git-ignored) is for development and command-line testing.

**Test Connection** in Settings shows the server, each library's size, and whether TMDB
accepted the key.

## Building

Open `Curator.xcodeproj` in Xcode and run the **Curator** scheme. Debug builds sign with
Apple Development for team `XV8BAAVZ6V`.

To build and test without signing:

```sh
xcodebuild build -project Curator.xcodeproj -scheme Curator \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

xcodebuild test -project Curator.xcodeproj -scheme Curator \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Never pass `-allowProvisioningUpdates`. It lets Xcode create or revoke certificates
without asking.

## Installing on another Mac

```sh
./scripts/make-dmg.sh
```

This archives a Release build and exports it signed with **Developer ID Application**,
using manual signing so nothing contacts the developer portal. It then packages a
drag-to-Applications DMG in `dist/`.

The DMG is **not notarized**, so Gatekeeper blocks it the first time:

- Copy it with `scp`, `rsync` or a file share, which don't mark files as downloaded, and
  it opens normally.
- If it arrived by AirDrop or a browser, open it once with **System Settings → Privacy &
  Security → Open Anyway**.

On first launch, allow Curator on the local network, then open Settings.

## How it works

- **`PlexClient`** is a small async client for Plex's HTTP API. It always requests JSON,
  sends the token as a header, and percent-encodes query values strictly. Searches use
  two endpoints: `/library/sections/{id}/all?title=` (complete, word-prefix matching) and
  `/hubs/search` (fuzzy, and includes cast and crew). Their results are merged.
- **`AppModel`** owns all long-running work: connecting, checking the TMDB key, polling
  Recently Added, and reloading after a reconnect. Views never start or cancel network
  requests. They render store state and send intents.
- **Stores** (`SearchStore`, `BrowseStore`, `RecentStore`, `ItemDetailStore`) each own
  their tasks. They tag results with a generation number, so a late or cancelled
  response can't overwrite newer state. `StoreConcurrencyTests` covers these races with
  a stubbed network that adds delays.
- **Artwork** loads off the main actor, is downsampled, and is cached in memory and on
  disk.

[`PLAN.md`](PLAN.md) has the design notes and milestones.

## Project layout

```
Curator/            App sources (Plex, TMDB, Library, Settings, Views, Artwork, Support)
  AppIcon.icon/     Icon Composer icon
  Assets.xcassets/  Accent color and the curator.bust menu bar symbol
CuratorTests/       Swift Testing unit tests
Config/Info.plist   Local-network ATS exception
scripts/            make-dmg.sh
Tools/              trace_icon.py (regenerates the icon and symbol from Curator.png)
```

## License

MIT. See [LICENSE](LICENSE).
