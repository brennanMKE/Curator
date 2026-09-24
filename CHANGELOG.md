# Changelog

Release notes for each version. `scripts/publish-release.sh` uses the section for the version
being released.

## 0.1.0

Playlists. Build a Die Hard marathon in a few clicks, and play it on any Plex app, including
Apple TV.

- **Add to Playlist:** right-click any poster. Your three most recently changed playlists are
  right there, the rest are under All Playlists, and New Playlist… starts one with that title.
- **Drag and drop:** drag a poster onto a playlist in the sidebar to add it, or onto New
  Playlist to start one. The sidebar lists your five most recently changed playlists.
- **Playlists:** open one to see its titles in order with the total runtime. Drag to reorder,
  press Delete to remove, and rename, delete or open it in Plex from the toolbar.
- **Undo:** a banner confirms each change, with Undo when you add a title. Titles already in a
  playlist aren't added twice.

## 0.0.4

Sort search results.

- **Search results** now have the same Sort menu as your libraries, and share its setting.
  Title matches and cast/crew matches are sorted separately, and cast/crew matches still say
  why they matched.
- Titles sort the way Plex does, so "The Big Lebowski" files under B. Titles with no rating or
  release date go last.

## 0.0.3

Sort your libraries.

- **Sort** Movies and TV Shows by title, release date, date added or rating, from the new Sort
  menu in the toolbar. Each has a natural order (A to Z, newest first, highest first) that you
  can flip, and Curator remembers your choice.
- Each poster's second line shows what it's sorted by: the release date, when it was added, or
  its rating.

## 0.0.2

Fixes a crash and smooths out the poster grid.

- **Fixed:** Curator could crash while you resized its window, or when the details panel
  opened.
- **Smoother grid:** clicking a poster no longer scrolls the grid, the banner for a new import
  no longer shifts the posters, and the once-a-minute refresh no longer redraws the grid when
  nothing changed.
- **Menu bar:** Open Curator, Settings and Quit are now icons.

## 0.0.1

The first release.

- **Recently Added** across your Plex libraries, grouped by day. It refreshes every minute,
  marks anything imported in the last 3 hours as NEW, and shows a banner when a title arrives.
- **Search** by title, actor or director. Matches on cast or crew say why they matched.
- **Browse** Movies and TV Shows.
- **Details** for the selected title: artwork, summary, cast, when it was added, the video
  format, and the file path and size on the server, with **Open in Plex**.
- **Menu bar** list of the last 5 imports.
- **Grid or list** view, arrow keys to move, Return to open in Plex, Space for a preview.
- **Settings** with step-by-step help for finding your Plex token and an optional TMDB key.
  Artwork comes from TMDB when you add a key, and from Plex otherwise.
