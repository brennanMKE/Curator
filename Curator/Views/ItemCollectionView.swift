import SwiftUI

enum ViewMode: String, CaseIterable {
    case grid, list

    static let storageKey = "viewMode"
}

struct ItemSection: Identifiable {
    let id: String
    let title: String?
    let items: [PlexItem]
}

/// Actions on an item that the window provides: Space previews it, Return opens it in Plex.
struct ItemActions {
    var preview: (PlexItem) -> Void = { _ in }
    var open: (PlexItem) -> Void = { _ in }
    /// Opens the New Playlist sheet starting with this title.
    var newPlaylist: (PlaylistCandidate) -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var itemActions = ItemActions()
}

/// Editing a playlist in place: Delete removes the selected title, and dropping one title on
/// another moves it there.
struct CollectionEditing {
    var remove: (PlexItem) -> Void
    /// Moves the dragged entry to the target's place; `false` if the drop isn't a move.
    var move: (_ dragged: PlaylistCandidate, _ target: PlexItem) -> Bool
}

/// Items in titled sections, as a poster grid or a list. Both layouts share one scroll view and
/// one key handler: arrows move the selection, Return opens in Plex, Space previews, and
/// double-click opens. `List` isn't used for the list layout because it stops taking arrow keys
/// once its rows are draggable.
struct ItemCollectionView: View {
    let sections: [ItemSection]
    @Binding var selection: PlexItem?
    var subtitle: (PlexItem) -> String? = { $0.displaySubtitle }
    var isNew: (PlexItem) -> Bool = { _ in false }
    var onReachEnd: (() -> Void)?
    /// Changing this scrolls back to the top.
    var scrollToTop = 0
    /// Numbers the list rows, for a playlist's order.
    var numbered = false
    var editing: CollectionEditing?
    /// Overrides the cells' accessibility identifier ("poster" or "itemRow").
    var cellIdentifier: String?

    @AppStorage(ViewMode.storageKey) private var viewMode = ViewMode.grid
    @Environment(\.itemActions) private var actions
    @FocusState private var isFocused: Bool
    @State private var metrics = GridMetrics()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Group {
                    switch viewMode {
                    case .grid: PosterGrid(sections: sections, cell: cell)
                    case .list: ItemList(sections: sections, cell: cell)
                    }
                }
                .id("top")
                // Written from inside AppKit's layout pass, so it must not be observed state: a
                // @State width here re-rendered the grid on every resize frame and crashed 0.0.1
                // (_postWindowNeedsUpdateConstraints). Only the arrow-key maths reads it.
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { metrics.width = $0 }
            }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return, .space, .delete, .deleteForward]) { press in
                handle(press.key, proxy: proxy)
            }
            .onChange(of: scrollToTop) {
                withAnimation { proxy.scrollTo("top", anchor: .top) }
            }
        }
    }

    private func cell(_ item: PlexItem, _ index: Int) -> CollectionCell {
        CollectionCell(
            item: item,
            mode: viewMode,
            number: numbered ? number(of: item) : nil,
            subtitle: subtitle(item),
            isNew: isNew(item),
            isSelected: selection?.entryID == item.entryID,
            isAlternate: index.isMultiple(of: 2) == false,
            identifier: cellIdentifier ?? (viewMode == .grid ? "poster" : "itemRow"),
            editing: editing,
            select: {
                selection = item
                isFocused = true
            },
            reachedEnd: item.entryID == sections.last?.items.last?.entryID ? onReachEnd : nil
        )
    }

    private func handle(_ key: KeyEquivalent, proxy: ScrollViewProxy) -> KeyPress.Result {
        switch key {
        case .return:
            guard let selection else { return .ignored }
            actions.open(selection)
        case .space:
            guard let selection else { return .ignored }
            actions.preview(selection)
        case .delete, .deleteForward:
            guard let editing, let selection else { return .ignored }
            // Keep a selection so Delete can be pressed again: the next title, or the one before.
            let items = sections.flatMap(\.items)
            let index = items.firstIndex { $0.entryID == selection.entryID }
            let neighbor = index.flatMap { index in
                items.indices.contains(index + 1) ? items[index + 1] : index > 0 ? items[index - 1] : nil
            }
            editing.remove(selection)
            self.selection = neighbor
        default:
            let direction: GridNavigation.Direction
            switch (key, viewMode) {
            case (.upArrow, _): direction = .up
            case (.downArrow, _): direction = .down
            case (.leftArrow, .grid): direction = .left
            case (.rightArrow, .grid): direction = .right
            default: return .ignored
            }
            let columns = viewMode == .grid
                ? GridNavigation.columns(width: metrics.width - 2 * PosterGrid.padding, minimum: PosterGrid.minimum, spacing: PosterGrid.spacing)
                : 1
            guard let next = GridNavigation.move(from: position(of: selection), direction, counts: sections.map(\.items.count), columns: columns) else {
                return .handled
            }
            let item = sections[next.section].items[next.index]
            selection = item
            // Only keyboard moves scroll; a click selects something already on screen, and
            // scrolling then made the grid jump.
            proxy.scrollTo(item.entryID)
        }
        return .handled
    }

    private func position(of item: PlexItem?) -> GridNavigation.Position? {
        guard let item else { return nil }
        for (sectionIndex, section) in sections.enumerated() {
            if let index = section.items.firstIndex(where: { $0.entryID == item.entryID }) {
                return GridNavigation.Position(section: sectionIndex, index: index)
            }
        }
        return nil
    }

    private func number(of item: PlexItem) -> Int? {
        sections.flatMap(\.items).firstIndex { $0.entryID == item.entryID }.map { $0 + 1 }
    }
}

/// The grid's width, for the arrow-key maths only. A plain class held in @State: writing it
/// doesn't invalidate the view.
private final class GridMetrics {
    var width: CGFloat = 0
}

// MARK: - Layouts

private struct PosterGrid: View {
    let sections: [ItemSection]
    let cell: (PlexItem, Int) -> CollectionCell

    static let minimum: CGFloat = 140
    static let spacing: CGFloat = 20
    static let padding: CGFloat = 20
    private let columns = [GridItem(.adaptive(minimum: minimum, maximum: 180), spacing: spacing, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 24, pinnedViews: .sectionHeaders) {
            ForEach(sections) { section in
                Section {
                    ForEach(Array(section.items.enumerated()), id: \.element.entryID) { index, item in
                        cell(item, index)
                    }
                } header: {
                    if let title = section.title {
                        SectionHeader(title: title, font: .title3.bold())
                    }
                }
            }
        }
        .padding(Self.padding)
    }
}

private struct ItemList: View {
    let sections: [ItemSection]
    let cell: (PlexItem, Int) -> CollectionCell

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
            ForEach(sections) { section in
                Section {
                    ForEach(Array(section.items.enumerated()), id: \.element.entryID) { index, item in
                        cell(item, index)
                    }
                } header: {
                    if let title = section.title {
                        SectionHeader(title: title, font: .headline)
                            .padding(.horizontal, 10)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct SectionHeader: View {
    let title: String
    let font: Font

    var body: some View {
        Text(title)
            .font(font)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .background(.background)
    }
}

// MARK: - Cells

/// One title in either layout. Click selects, double-click opens in Plex, and it can be dragged
/// onto a playlist; when editing, it also takes drops to reorder.
private struct CollectionCell: View {
    let item: PlexItem
    let mode: ViewMode
    let number: Int?
    let subtitle: String?
    let isNew: Bool
    let isSelected: Bool
    let isAlternate: Bool
    let identifier: String
    let editing: CollectionEditing?
    let select: () -> Void
    let reachedEnd: (() -> Void)?

    @Environment(\.itemActions) private var actions
    @Environment(NowPlayingStore.self) private var nowPlaying
    @State private var isTargeted = false

    var body: some View {
        Button(action: select) {
            switch mode {
            case .grid:
                PosterCard(item: item, subtitle: subtitle, isNew: isNew, nowPlaying: nowPlaying.state(for: item), isSelected: isSelected || isTargeted)
            case .list:
                ItemRow(item: item, number: number, subtitle: subtitle, isNew: isNew, nowPlaying: nowPlaying.state(for: item), isSelected: isSelected)
                    .background(rowBackground, in: .rect(cornerRadius: 5))
                    .overlay {
                        if isTargeted {
                            RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accentColor, lineWidth: 2)
                        }
                    }
            }
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture(count: 2).onEnded { actions.open(item) })
        .accessibilityIdentifier(identifier)
        .id(item.entryID)
        .draggable(PlaylistCandidate(item)) { DragPreview(title: item.displayTitle) }
        .dropDestination(for: PlaylistCandidate.self) { candidates, _ in
            guard let editing, let dragged = candidates.first else { return false }
            return editing.move(dragged, item)
        } isTargeted: { targeted in
            // A drop only means something here while editing a playlist.
            isTargeted = targeted && editing != nil
        }
        .contextMenu {
            if let editing {
                Button("Remove from Playlist") { editing.remove(item) }
                Divider()
            }
            ItemContextMenu(item: item)
        }
        .onAppear { reachedEnd?() }
    }

    private var rowBackground: AnyShapeStyle {
        if isSelected { AnyShapeStyle(Color.accentColor.opacity(0.3)) }
        else if isAlternate { AnyShapeStyle(.primary.opacity(0.04)) }
        else { AnyShapeStyle(.clear) }
    }
}

struct PosterCard: View {
    let item: PlexItem
    let subtitle: String?
    let isNew: Bool
    var nowPlaying: NowPlaying?
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay { ArtworkView(item: item, kind: .poster) }
                .clipShape(.rect(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : .primary.opacity(0.1), lineWidth: isSelected ? 3 : 1)
                }
                .overlay(alignment: .topLeading) {
                    if isNew { NewBadge().padding(6) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if let nowPlaying { NowPlayingBadge(nowPlaying: nowPlaying).padding(6) }
                }
                .shadow(color: .black.opacity(0.15), radius: 3, y: 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(.rect)
        .help(item.displayTitle)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ItemRow: View {
    let item: PlexItem
    let number: Int?
    let subtitle: String?
    let isNew: Bool
    let nowPlaying: NowPlaying?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let number {
                Text("\(number)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
            }
            Color.clear
                .frame(width: 28, height: 42)
                .overlay { ArtworkView(item: item, kind: .poster) }
                .clipShape(.rect(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayTitle)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let nowPlaying { NowPlayingBadge(nowPlaying: nowPlaying) }
            if isNew { NewBadge() }
            if let media = item.media.first {
                Text(Format.mediaSummary(media))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .trailing)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Shared

struct NewBadge: View {
    var body: some View {
        Text("NEW")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.tint, in: .capsule)
            // Near-black on Plex gold, as Plex does; white on gold is too faint.
            .foregroundStyle(Color(white: 0.1))
    }
}

/// Play or pause, in Plex gold like the NEW badge; the tooltip names the player.
struct NowPlayingBadge: View {
    let nowPlaying: NowPlaying

    var body: some View {
        Image(systemName: nowPlaying.state == .paused ? "pause.fill" : "play.fill")
            .font(.caption.bold())
            .frame(width: 22, height: 22)
            .background(.tint, in: .circle)
            .foregroundStyle(Color(white: 0.1))
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .help(nowPlaying.description)
            .accessibilityLabel(nowPlaying.description)
            .accessibilityIdentifier("nowPlayingBadge")
    }
}

struct ItemContextMenu: View {
    let item: PlexItem

    @Environment(\.itemActions) private var actions

    var body: some View {
        Button("Open in Plex") { actions.open(item) }
        Button("Quick Look") { actions.preview(item) }
        Divider()
        AddToPlaylistMenu(candidate: PlaylistCandidate(item))
        Divider()
        Button("Copy Title") { copy(item.displayTitle) }
        if let path = item.filePath {
            Button("Copy File Path") { copy(path) }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Add to Playlist ▸ the 3 most recently changed, All Playlists ▸ (when there are more), and
/// New Playlist….
struct AddToPlaylistMenu: View {
    let candidate: PlaylistCandidate

    @Environment(PlaylistStore.self) private var playlists
    @Environment(\.itemActions) private var actions

    var body: some View {
        Menu("Add to Playlist") {
            ForEach(playlists.recent) { playlist in
                Button(playlist.title) { playlists.add(candidate, to: playlist) }
            }
            if playlists.playlists.count > PlaylistStore.recentCount {
                Divider()
                Menu("All Playlists") {
                    ForEach(playlists.alphabetical) { playlist in
                        Button(playlist.title) { playlists.add(candidate, to: playlist) }
                    }
                }
            }
            if !playlists.playlists.isEmpty { Divider() }
            Button("New Playlist…") { actions.newPlaylist(candidate) }
        }
    }
}

/// What follows the pointer while dragging a title.
struct DragPreview: View {
    let title: String

    var body: some View {
        Label(title, systemImage: "film")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: .capsule)
    }
}
