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
}

extension EnvironmentValues {
    @Entry var itemActions = ItemActions()
}

/// Items in titled sections, as a poster grid or a list. Both support the keyboard:
/// arrows move the selection, Return opens in Plex, Space previews.
struct ItemCollectionView: View {
    let sections: [ItemSection]
    @Binding var selection: PlexItem?
    var subtitle: (PlexItem) -> String? = { $0.displaySubtitle }
    var isNew: (PlexItem) -> Bool = { _ in false }
    var onReachEnd: (() -> Void)?
    /// Changing this scrolls back to the top.
    var scrollToTop = 0

    @AppStorage(ViewMode.storageKey) private var viewMode = ViewMode.grid

    var body: some View {
        switch viewMode {
        case .grid:
            PosterGridView(sections: sections, selection: $selection, subtitle: subtitle, isNew: isNew, onReachEnd: onReachEnd, scrollToTop: scrollToTop)
        case .list:
            ItemListView(sections: sections, selection: $selection, subtitle: subtitle, isNew: isNew, onReachEnd: onReachEnd, scrollToTop: scrollToTop)
        }
    }
}

// MARK: - Grid

private struct PosterGridView: View {
    let sections: [ItemSection]
    @Binding var selection: PlexItem?
    let subtitle: (PlexItem) -> String?
    let isNew: (PlexItem) -> Bool
    let onReachEnd: (() -> Void)?
    let scrollToTop: Int

    @Environment(\.itemActions) private var actions
    @FocusState private var isFocused: Bool
    @State private var width: CGFloat = 0

    private static let minimum: CGFloat = 140
    private static let spacing: CGFloat = 20
    private static let padding: CGFloat = 20
    private let columns = [GridItem(.adaptive(minimum: minimum, maximum: 180), spacing: spacing, alignment: .top)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24, pinnedViews: .sectionHeaders) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.items) { item in
                                Button {
                                    selection = item
                                    isFocused = true
                                } label: {
                                    PosterCard(item: item, subtitle: subtitle(item), isNew: isNew(item), isSelected: selection?.id == item.id)
                                }
                                .buttonStyle(.plain)
                                .contextMenu { ItemContextMenu(item: item) }
                                .onAppear {
                                    if item.id == sections.last?.items.last?.id { onReachEnd?() }
                                }
                            }
                        } header: {
                            if let title = section.title {
                                SectionHeader(title: title)
                            }
                        }
                    }
                }
                .padding(Self.padding)
                .id("top")
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return, .space]) { press in
                handle(press.key)
            }
            .onChange(of: selection?.id) {
                guard let id = selection?.id else { return }
                withAnimation { proxy.scrollTo(id) }
            }
            .onChange(of: scrollToTop) {
                withAnimation { proxy.scrollTo("top", anchor: .top) }
            }
        }
    }

    private func handle(_ key: KeyEquivalent) -> KeyPress.Result {
        switch key {
        case .return:
            guard let selection else { return .ignored }
            actions.open(selection)
        case .space:
            guard let selection else { return .ignored }
            actions.preview(selection)
        default:
            let direction: GridNavigation.Direction = switch key {
            case .leftArrow: .left
            case .rightArrow: .right
            case .upArrow: .up
            default: .down
            }
            let columns = GridNavigation.columns(width: width - 2 * Self.padding, minimum: Self.minimum, spacing: Self.spacing)
            guard let next = GridNavigation.move(from: position(of: selection), direction, counts: sections.map(\.items.count), columns: columns) else {
                return .handled
            }
            selection = sections[next.section].items[next.index]
        }
        return .handled
    }

    private func position(of item: PlexItem?) -> GridNavigation.Position? {
        guard let item else { return nil }
        for (sectionIndex, section) in sections.enumerated() {
            if let index = section.items.firstIndex(where: { $0.id == item.id }) {
                return GridNavigation.Position(section: sectionIndex, index: index)
            }
        }
        return nil
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .background(.background)
    }
}

struct PosterCard: View {
    let item: PlexItem
    let subtitle: String?
    let isNew: Bool
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

// MARK: - List

private struct ItemListView: View {
    let sections: [ItemSection]
    @Binding var selection: PlexItem?
    let subtitle: (PlexItem) -> String?
    let isNew: (PlexItem) -> Bool
    let onReachEnd: (() -> Void)?
    let scrollToTop: Int

    @Environment(\.itemActions) private var actions

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: selectedID) {
                ForEach(sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            ItemRow(item: item, subtitle: subtitle(item), isNew: isNew(item))
                                .tag(item.id)
                                .onAppear {
                                    if item.id == sections.last?.items.last?.id { onReachEnd?() }
                                }
                        }
                    } header: {
                        if let title = section.title { Text(title) }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            // Double-click or Return opens in Plex, like opening a file in Finder.
            .contextMenu(forSelectionType: String.self) { ids in
                if let item = ids.first.flatMap(item(withID:)) {
                    ItemContextMenu(item: item)
                }
            } primaryAction: { ids in
                if let item = ids.first.flatMap(item(withID:)) { actions.open(item) }
            }
            .onKeyPress(.space) {
                guard let selection else { return .ignored }
                actions.preview(selection)
                return .handled
            }
            .onChange(of: scrollToTop) {
                if let first = sections.first?.items.first { withAnimation { proxy.scrollTo(first.id, anchor: .top) } }
            }
        }
    }

    private var selectedID: Binding<String?> {
        Binding {
            selection?.id
        } set: { id in
            selection = id.flatMap(item(withID:))
        }
    }

    private func item(withID id: String) -> PlexItem? {
        for section in sections {
            if let item = section.items.first(where: { $0.id == id }) { return item }
        }
        return nil
    }
}

private struct ItemRow: View {
    let item: PlexItem
    let subtitle: String?
    let isNew: Bool

    var body: some View {
        HStack(spacing: 10) {
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
            if isNew { NewBadge() }
            if let media = item.media.first {
                Text(Format.mediaSummary(media))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .trailing)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
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
            .foregroundStyle(.white)
    }
}

struct ItemContextMenu: View {
    let item: PlexItem

    @Environment(\.itemActions) private var actions

    var body: some View {
        Button("Open in Plex") { actions.open(item) }
        Button("Quick Look") { actions.preview(item) }
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
