import SwiftUI

struct PosterSection: Identifiable {
    let id: String
    let title: String?
    let items: [PlexItem]
}

/// An adaptive grid of posters in titled sections. Selecting a poster shows it in the inspector.
struct PosterGrid: View {
    let sections: [PosterSection]
    @Binding var selection: PlexItem?
    var subtitle: (PlexItem) -> String? = { $0.displaySubtitle }
    var isNew: (PlexItem) -> Bool = { _ in false }
    var onReachEnd: (() -> Void)?
    /// Changing this scrolls back to the top.
    var scrollToTop = 0

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 20, alignment: .top)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24, pinnedViews: .sectionHeaders) {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.items) { item in
                                Button {
                                    selection = item
                                } label: {
                                    PosterCard(
                                        item: item,
                                        subtitle: subtitle(item),
                                        isNew: isNew(item),
                                        isSelected: selection?.id == item.id
                                    )
                                }
                                .buttonStyle(.plain)
                                .onAppear {
                                    if item.id == sections.last?.items.last?.id { onReachEnd?() }
                                }
                            }
                        } header: {
                            if let title = section.title {
                                Text(title)
                                    .font(.title3.bold())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .background(.background)
                            }
                        }
                    }
                }
                .padding(20)
                .id("top")
            }
            .onChange(of: scrollToTop) {
                withAnimation { proxy.scrollTo("top", anchor: .top) }
            }
        }
    }
}

struct PosterCard: View {
    let item: PlexItem
    let subtitle: String?
    let isNew: Bool
    let isSelected: Bool

    @Environment(LibraryStore.self) private var library
    @Environment(SettingsStore.self) private var settings

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
                    if isNew {
                        Text("NEW")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint, in: .capsule)
                            .foregroundStyle(.white)
                            .padding(6)
                    }
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
        .contextMenu {
            if let server = library.server, let url = settings.plexClient?.webURL(for: item, machineIdentifier: server.machineIdentifier) {
                Link("Open in Plex", destination: url)
            }
            Button("Copy Title") { copy(item.displayTitle) }
            if let path = item.filePath {
                Button("Copy File Path") { copy(path) }
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
