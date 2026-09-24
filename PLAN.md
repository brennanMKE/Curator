# Curator — plan

A native SwiftUI Mac app for browsing the Plex library on joe: **Recently Added** (default
view, for watching imports land) and **Search**, plus a Settings window. It talks to Plex's
HTTP API as JSON and pulls artwork from TMDB.

Reference docs: `~/Developer/Homelab/docs/plex-search-api.md` and
`~/Developer/Homelab/docs/plex-library-on-joe.md`.

## Settings

Every Plex library call needs the **Plex token** (401 without it), so Settings has three
fields:

| Field | `.env` key | Default |
|---|---|---|
| Plex server URL | `PLEX_URL` | `http://joe:32400` |
| Plex token | `PLEX_TOKEN` | — (help: `ssh joe 'defaults read com.plexapp.plexmediaserver PlexOnlineToken'`) |
| TMDB API key | `TMDB_API_KEY` | — (v3 key or v4 read token) |

Values live in a `.env` file (mode 0600) in the app's Application Support folder, with the
same keys as the repo's `.env.example`. Settings has step-by-step help for finding each
value (no Terminal needed). Curator never uses the Keychain.

**Test Connection** hits `/` (name + version) and `/library/sections` and shows the server,
the libraries and their item counts, or a specific error ("401: token rejected"). Section
ids are discovered from `/library/sections`, never hardcoded (Movies is 4, TV Shows is 2
today).

## Main window

`NavigationSplitView`:

- **Sidebar:** Recently Added · Movies · TV Shows, with live counts.
- **Toolbar:** search field (⌘F), grid/list toggle, Refresh (⌘R).
- **Detail inspector** (select a poster): backdrop, title, year, runtime, summary,
  resolution/codec, **added-at timestamp and file path on disk**, and **Open in Plex Web**.

### Recently Added

- `GET /library/sections/{id}/all?sort=addedAt%3Adesc` with **both**
  `X-Plex-Container-Start` and `X-Plex-Container-Size` (one alone is silently ignored).
  Page 50 at a time, infinite scroll.
- Grouped **Today / Yesterday / This Week / Earlier** with relative times.
- **NEW badge** for anything imported in the last 3 hours.
- Auto-refresh every 60 s while the window is visible; banner "2 new titles" when an import
  lands.

### Search

Debounced (300 ms) as-you-type, two queries in parallel, merged by `ratingKey`:

1. `/library/sections/{id}/all?title=` per library — complete, reliable, word-prefix.
2. `/hubs/search?query=&limit=20` — adds cast/crew ("Belushi", "Coen") and misspellings.

Title matches first; hub-only hits in a **"Matched cast/crew"** section with the reason.
Empty state explains word-prefix matching and that an unmatched file on disk won't appear.

## Artwork

1. Request Plex items with `includeGuids=1` to read `tmdb://ID` from `Guid[]`.
   Verified on joe 2026-09-22: `Guid` returns `imdb://`, `tmdb://` and `tvdb://` ids.
2. TMDB `GET /3/movie/{id}` or `/3/tv/{id}` → `poster_path`/`backdrop_path`; images from
   `image.tmdb.org/t/p/w342` (grid) and `w1280` (detail).
3. **Fallback:** Plex's own poster via `/photo/:/transcode?width=342&height=513&url={thumb}`.
4. Cache TMDB metadata on disk by TMDB id; images via `URLCache` + `NSCache`.

## Architecture

```
Curator/
  CuratorApp.swift         WindowGroup + Settings scene
  Settings/SettingsStore   @Observable; .env file in Application Support
  Settings/SettingsView    fields + Test Connection
  Plex/PlexClient          async URLSession, Accept: application/json, token header
  Plex/PlexModels          Codable: MediaContainer, Metadata, Guid, Media, Part, Hub
  TMDB/TMDBClient          poster/backdrop lookup, v3 key or v4 bearer
  Artwork/ArtworkLoader    TMDB → Plex fallback, caching
  Library/RecentModel      paging, polling, "new since" tracking
  Library/SearchModel      debounce, parallel queries, merge/rank
  Views/                   Sidebar, PosterGrid, PosterCard, DetailInspector, EmptyStates
```

- macOS 26, Swift 6 language mode, MainActor default isolation, `@Observable`,
  async/await. No dependencies.
- **Networking is isolated from views.** `AppModel` owns connecting, the TMDB check,
  polling and reloads after a reconnect. Views never start or cancel requests: they render
  store state and send intents (`refresh()`, `search.query = …`, `loadNextPage()`). Each
  store owns its tasks and tags results with a generation (search results also carry their
  query), so a cancelled or late response can't overwrite newer state. `PlexClient` and
  `TMDBClient` do their requests and JSON decoding off the main actor (`@concurrent`).
  `StoreConcurrencyTests` covers the races with a stubbed, delayed network.
- Signing, as in Batty: builds use **Apple Development** (Automatic, team XV8BAAVZ6V,
  hardened runtime); **Developer ID Application** is applied when a release is archived
  and exported. Never `-allowProvisioningUpdates`. Agents build and test unsigned
  (`CODE_SIGNING_ALLOWED=NO`) unless the user asks for a signed build and is present.
- Plain HTTP to joe: `NSAllowsLocalNetworking` (ATS), `NSLocalNetworkUsageDescription`,
  sandbox outgoing-network entitlement.
- Guard against Plex's silent failures: only send known filter fields (a bad field returns
  the whole library), sanity-check against unfiltered `totalSize`, percent-encode operators.

## Milestones

1. ✅ **Settings & connection** — Settings window, Keychain, Test Connection, library
   discovery.
2. ✅ **Recently Added** — paging, grouping, Plex posters, detail inspector.
3. ✅ **Search** — dual-query merge, cast/crew section, empty states.
4. ✅ **TMDB artwork** — guid extraction, lookup, caching, Plex fallback.
5. ✅ **Polish** — grid/list toggle (remembered); arrows move the selection across sections
   in the grid (the list gets it natively); Return or double-click opens in Plex; Space opens
   a Quick Look–style preview. Colors are semantic throughout. Still needs a visual pass in
   light mode on a live library.

Feature gating: everything needs a working Plex connection (otherwise the window shows how
to connect). TMDB is optional — artwork uses it only while the key validates, and falls back
to Plex's own posters when it's missing, rejected or unreachable.

## Milestone 6: releases (modelled on Batty)

Goal: notarized, versioned releases people can download from a website, with Sparkle
updates. Batty (`../Batty`) already does all of this; copy its approach, minus its
embedded CLI/broker/XPC parts.

- **Versions.** Move `MARKETING_VERSION` into `Configuration/App.xcconfig` (the single
  source of truth, not the pbxproj). The build number is set at archive time to the UTC
  date. Guards: `release.sh` checks the built bundle matches; `preflight.sh` fails if the
  version wasn't bumped past the newest appcast item.
- **Sparkle.** Add Sparkle 2 by SPM. Info.plist keys `SUFeedURL`, `SUPublicEDKey` and
  `SUEnableAutomaticChecks`, fed from xcconfig (`SU_FEED_URL`, `SU_PUBLIC_ED_KEY`). An
  `UpdaterController` wraps `SPUStandardUpdaterController`, and a **Check for Updates…**
  menu item goes in the app menu. The EdDSA key is generated with
  `generate_keys --account Curator`, and must be backed up.
- **Scripts.** Adapt from Batty or the mac-release skill templates:
  - `preflight.sh`: credentials, versions and a clean tree
  - `release.sh`: archive, Developer ID export, DMG, sign, notarize, staple, verify
  - `verify-dmg.sh`
  - `appcast-item.sh`: every attribute is read from the DMG
  - `tag-release.sh`
  - `update-website.sh`: the feed entry, changelog and download button. Deploying the site
    is a separate agent's job, and it takes the DMGs from GitHub releases.
  - Notarizing uses the existing App Store Connect API key file directly; no notarytool
    profile.
  - `scripts/make-dmg.sh` stays for quick non-notarized builds.
- **Website.** A `website/` folder (index, changelog, privacy, `appcast.xml`,
  `downloads/`), deployed like Batty's (rsync to the web host).
- **Where releases run.** On a Mac with the notary profile and Sparkle key. Today that's
  the MacBook Air; `RELEASE-CREDENTIALS.md` explains how to move them. Notarizing and
  publishing are always run by a person.

Decisions needed: the website domain and host (for example, `curator.sstools.co` on the
same host as Batty), and the first public version number.

## Milestone 7: playlists (0.1.0)

Add to Playlist in every context menu (3 recent shortcuts, All Playlists, New Playlist…), the
five most recently changed playlists in the sidebar as drop targets, and a playlist view to
reorder, remove, rename and delete. Design and Plex API findings: `docs/playlists.md`.

## Idea: show the title on the Apple TV

Plex apps that act as players can be controlled over Plex's remote-control
("Companion") API: `…/player/mirror/details?key=/library/metadata/{id}` shows an item's
page, and `…/player/playback/playMedia` starts it. Curator could add a **Show on Apple
TV** button if the Plex app on the Apple TV registers as a player. On 2026-09-23 the
account listed no players: `/clients` and plex.tv resources showed only the server. Next
step: with Plex open on the Apple TV, check whether it appears. If it doesn't, the
current tvOS app may not support remote control.

## Later (not v1)

- Menu bar extra showing the last 5 imports.
- "On disk but not in Plex" check (the `Knowing` case) — needs SSH or a helper on joe.
- Signed DMG distribution to other Macs (`mac-release` skill).
