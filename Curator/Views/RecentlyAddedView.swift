import SwiftUI

struct RecentlyAddedView: View {
    @Binding var selection: PlexItem?

    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(RecentStore.self) private var recent
    @State private var scrollToTop = 0

    private static let pollInterval: Duration = .seconds(60)

    var body: some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if !recent.arrivals.isEmpty {
                    ArrivalsBanner(arrivals: recent.arrivals) {
                        scrollToTop += 1
                        selection = recent.arrivals.first
                        recent.dismissArrivals()
                    } dismiss: {
                        recent.dismissArrivals()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: recent.arrivals.map(\.id))
            .navigationTitle("Recently Added")
            .navigationSubtitle(subtitle)
            .toolbar {
                ToolbarItem {
                    Button("Mark All as Seen", systemImage: "checkmark.circle") {
                        recent.markAllSeen()
                    }
                    .help("Clear the New badges")
                    .disabled(recent.newCount == 0)
                }
            }
            // Load on connect, then poll so imports show up on their own.
            .task(id: library.revision) {
                guard let client = settings.plexClient else { return }
                await recent.load(client: client, sections: library.sections, reset: !recent.hasLoaded)
                while !Task.isCancelled {
                    try? await Task.sleep(for: Self.pollInterval)
                    guard !Task.isCancelled, let client = settings.plexClient else { return }
                    await recent.load(client: client, sections: library.sections)
                    await library.refreshCounts(using: client)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if !recent.hasLoaded {
            if let error = recent.error {
                ContentUnavailableView(error.localizedDescription, systemImage: "exclamationmark.triangle", description: Text(error.recoverySuggestion ?? ""))
            } else {
                ProgressView("Loading recent additions…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if recent.items.isEmpty {
            ContentUnavailableView(
                "Nothing Here Yet",
                systemImage: "tray",
                description: Text("Movies and episodes will appear here as soon as Plex adds them.")
            )
        } else {
            TimelineView(.everyMinute) { context in
                PosterGrid(
                    sections: RecentGroup.sections(recent.items, now: context.date).map {
                        PosterSection(id: $0.group.rawValue, title: $0.group.rawValue, items: $0.items)
                    },
                    selection: $selection,
                    subtitle: { item in
                        [item.displaySubtitle, item.addedAt.map { Format.relative($0, to: context.date) }]
                            .compactMap(\.self)
                            .joined(separator: " · ")
                    },
                    isNew: recent.isNew,
                    onReachEnd: loadMore,
                    scrollToTop: scrollToTop
                )
            }
        }
    }

    private var subtitle: String {
        let count = recent.newCount
        return count == 0 ? "" : "\(count) new"
    }

    private func loadMore() {
        guard let client = settings.plexClient else { return }
        Task { await recent.loadMore(client: client, sections: library.sections) }
    }
}

private struct ArrivalsBanner: View {
    let arrivals: [PlexItem]
    let show: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.tint)
            Text(message)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Button("Show", action: show)
            Button("Dismiss", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var message: String {
        let titles = arrivals.prefix(2).map(\.displayTitle).joined(separator: ", ")
        switch arrivals.count {
        case 1: return "Just added: \(titles)"
        case 2: return "2 titles just added: \(titles)"
        default: return "\(arrivals.count) titles just added: \(titles) and more"
        }
    }
}
