import SwiftUI

/// The status bar icon, with a count while there are unseen imports.
struct MenuBarLabel: View {
    @Environment(RecentStore.self) private var recent

    var body: some View {
        let count = recent.newCount()
        HStack(spacing: 2) {
            Image(.curatorBust)
            if count > 0 {
                Text("\(count)")
            }
        }
        .accessibilityLabel(count > 0 ? "Curator, \(count) new" : "Curator")
    }
}

/// The status bar window: the newest imports at a glance.
struct MenuBarView: View {
    static let itemLimit = 5
    static let contentHeight: CGFloat = 300

    @Environment(AppModel.self) private var model
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(RecentStore.self) private var recent
    @Environment(NowPlayingStore.self) private var nowPlaying
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            // A fixed height: the status bar window sizes itself once, on first render,
            // and wouldn't grow when the list loads.
            content
                .frame(maxWidth: .infinity)
                .frame(height: Self.contentHeight)
                .clipped()
            Divider()
            footer
        }
        .frame(width: 340)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Recently Added").font(.headline)
                ConnectionStatusView()
            }
            Spacer()
            Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Refresh")
            .accessibilityIdentifier("menuBarRefresh")
            .disabled(!settings.isPlexConfigured || library.status == .connecting || recent.isLoading)
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        switch library.status {
        case .notConfigured:
            placeholder("Connect to Plex", systemImage: "server.rack", detail: "Open Settings to add your Plex server; it shows how to find each value.")
        case .failed(let error):
            placeholder(error.localizedDescription, systemImage: "exclamationmark.triangle", detail: error.recoverySuggestion)
        case .connecting, .connected:
            if !recent.hasLoaded {
                ProgressView().controlSize(.small).padding()
            } else if recent.items.isEmpty {
                placeholder("Nothing Here Yet", systemImage: "tray", detail: nil)
            } else {
                TimelineView(.everyMinute) { context in
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(recent.items.prefix(Self.itemLimit)) { item in
                                MenuBarRow(item: item, isNew: RecentStore.isNew(item, now: context.date), nowPlaying: nowPlaying.state(for: item), now: context.date) {
                                    show(item)
                                }
                            }
                        }
                        .padding(6)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Button("Open Curator", systemImage: "macwindow") { openMainWindow() }
                .help("Open Curator")
                .accessibilityIdentifier("menuBarOpen")
            Spacer()
            SettingsLink {
                Label("Settings…", systemImage: "gearshape")
            }
            .help("Settings")
            Button("Quit Curator", systemImage: "power") { NSApplication.shared.terminate(nil) }
                .help("Quit Curator")
        }
        .labelStyle(.iconOnly)
        .imageScale(.large)
        .buttonStyle(.borderless)
        .padding(12)
    }

    private func placeholder(_ title: String, systemImage: String, detail: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title).font(.callout.weight(.medium))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private func show(_ item: PlexItem) {
        navigation.pendingItem = item
        openMainWindow()
    }

    private func openMainWindow() {
        dismiss()
        openWindow(id: "main")
        NSApplication.shared.activate()
    }
}

private struct MenuBarRow: View {
    let item: PlexItem
    let isNew: Bool
    let nowPlaying: NowPlaying?
    let now: Date
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Color.clear
                    .frame(width: 32, height: 48)
                    .overlay { ArtworkView(item: item, kind: .poster) }
                    .clipShape(.rect(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayTitle)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text([item.displaySubtitle, item.addedAt.map { Format.relative($0, to: now) }].compactMap(\.self).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let nowPlaying { NowPlayingBadge(nowPlaying: nowPlaying) }
                if isNew { NewBadge() }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("menuBarRow")
        .onHover { isHovered = $0 }
    }
}
