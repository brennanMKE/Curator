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
same keys as the repo's `.env.example`. **Import .env…** in Settings loads them from the
repo's `.env`. Curator never uses the Keychain.

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
- **"New" badge** for items added since you last looked (persisted `lastSeenAddedAt`).
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
5. **Polish** — keyboard nav (arrows, Return, Space), grid/list toggle, dark/light pass.
   Auto-refresh, New badges and Open in Plex landed with milestones 2–4.

Feature gating: everything needs a working Plex connection (otherwise the window shows how
to connect). TMDB is optional — artwork uses it only while the key validates, and falls back
to Plex's own posters when it's missing, rejected or unreachable.

## Later (not v1)

- Menu bar extra showing the last 5 imports.
- "On disk but not in Plex" check (the `Knowing` case) — needs SSH or a helper on joe.
- Signed DMG distribution to other Macs (`mac-release` skill).
