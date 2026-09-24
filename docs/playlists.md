# Playlists (0.1.0)

Build playlists, like a Die Hard marathon, from Curator: right-click a poster, or drag it
onto a playlist in the sidebar. The playlists live on the Plex server, so they play on every
Plex app, including Apple TV.

## What Plex does (checked against joe, 2026-09-24)

| Action | Request | Notes |
|---|---|---|
| List | `GET /playlists?playlistType=video` | `ratingKey`, `title`, `leafCount`, `duration` (ms), `addedAt`, `updatedAt`, `composite` (artwork) |
| Create | `POST /playlists?type=video&title=…&smart=0&uri=…` | `uri` is `server://{machineIdentifier}/com.plexapp.plugins.library/library/metadata/{ratingKey}` |
| Add | `PUT /playlists/{id}/items?uri=…` | Several items at once: comma-separated rating keys in one `uri`. Returns `leafCountAdded` |
| Items | `GET /playlists/{id}/items` | Each entry has a `playlistItemID`, used to remove or move it |
| Remove | `DELETE /playlists/{id}/items/{playlistItemID}` | |
| Move | `PUT /playlists/{id}/items/{playlistItemID}/move?after={playlistItemID}` | With no `after`, the item moves to the top |
| Rename | `PUT /playlists/{id}?title=…` | |
| Delete | `DELETE /playlists/{id}` | 204 |

Three findings shape the design:

- **Plex won't create an empty playlist** (`POST` without `uri` → HTTP 400). Every playlist
  starts with a title: from **New Playlist…** in the context menu, or by dropping a poster on
  the sidebar's **New Playlist** row. Clicking that row explains this rather than failing.
- **Plex skips duplicates silently.** Adding a movie that's already in the playlist returns
  `leafCountAdded: 0`. Curator reports "Already in …" rather than pretending it added it.
- **Plex's `updatedAt` doesn't change** when items are added or the playlist is renamed; it
  stays at the creation time. So "recently updated" is tracked by Curator: it records when it
  creates or changes a playlist (per server, in UserDefaults) and falls back to Plex's
  `addedAt` for playlists it hasn't touched.

## Design

### Adding from a poster: the context menu

Right-click any poster or list row (Recently Added, a library, search, or the menu bar
list's parent views):

```
Open in Plex
Quick Look
─────────────
Add to Playlist ▸   Die Hard Marathon          ← the 3 most recently changed
                    Friday Night
                    Comedies
                    ───────────
                    All Playlists ▸  (every playlist, A to Z; only when there are more than 3)
                    ───────────
                    New Playlist…
─────────────
Copy Title
Copy File Path
```

**New Playlist…** opens a small sheet asking for a name, with the title prefilled (e.g.
"Die Hard"). **Create** makes the playlist with that movie in it.

### Adding by drag and drop: the sidebar

The sidebar gets a **Playlists** section below Libraries:

```
Recently Added
Libraries
  Movies              61
  TV Shows
Playlists
  Die Hard Marathon    5      ← the 5 most recently changed; drop targets
  Friday Night         3
  All Playlists…              ← when there are more than 5
  + New Playlist              ← drop a poster here to start a playlist with it
```

- Drag a poster (grid) or a row (list) onto a playlist to add it. The row highlights while
  you're over it.
- Drag onto **New Playlist** to create a playlist that starts with that title.
- Selecting a playlist opens it.

### A playlist

Selecting a playlist shows its items in order:

- The header shows the name, count and total runtime ("5 movies · 10h 21m").
- It follows the toolbar's grid/list switch, like every other view. The list numbers the
  titles.
- Drag a title onto another to move it there: after it when dragging down, before it when
  dragging up. Remove with **Delete** or the context menu.
- Arrow keys, Return (open in Plex), Space (preview), double-click and the inspector work as
  elsewhere.

Every view, playlists included, uses the same `ItemCollectionView`: one scroll view with its
own key handling, laying out cells as a grid or a list. The list isn't a SwiftUI `List`,
because `List` stopped taking arrow keys once its rows were draggable (0.1.0).
- The toolbar has **Open in Plex**, **Rename…** and **Delete Playlist…**. Deleting asks for
  confirmation, because it deletes the playlist on the server for every Plex app.

### Feedback

Every change shows a short banner at the bottom of the window. It dismisses itself after a
few seconds:

- "Added Die Hard 2 to Die Hard Marathon" with **Undo**
- "Die Hard 2 is already in Die Hard Marathon"
- "Couldn't add Die Hard 2: Plex returned HTTP 500"

### Architecture

This follows the rules in PLAN.md: views send intents, and stores own their requests.

- `PlexClient` adds the playlist requests above, with a general request that can send `POST`,
  `PUT` or `DELETE`.
- `PlaylistStore` (`@Observable`, owned by `AppModel`, reloaded on every connect) holds the
  playlists, the "recently changed" order, and each opened playlist's items. It exposes
  intents: `create`, `add`, `remove`, `move`, `rename`, `delete` and `undo`. Each runs its own
  task and publishes one `event` for the banner.
- **Drag and drop** uses a `Transferable` `PlexItemDrag` with Curator's own type
  `co.sstools.curator.item`, declared in Info.plist. Only Curator's views accept it.
- `SidebarItem` gains `.playlist(id)` and `.allPlaylists`.

### Out of scope for 0.1.0

- Selecting several posters at once (drag or add one at a time).
- Smart playlists (Plex's rule-based ones are listed and playable, but not editable).
- Music and photo playlists (only video playlists are shown).

## Tests

- **Unit:** each request's method, path and `uri` encoding; recency ordering, including the
  fallback to `addedAt`; duplicate reporting; and undo removing only what was added.
- **UI, in the VM, against joe:**
  - create a playlist from the context menu
  - add a second movie from the recent shortcuts
  - drag a poster onto the sidebar playlist
  - reorder and remove in the playlist view

  Each test names its playlist `Curator UI Test <id>` and deletes it afterwards through Plex's
  API, even when it fails, so nothing is left on the server.
