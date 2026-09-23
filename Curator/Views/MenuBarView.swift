import SwiftUI

/// The status bar icon, with a count while there are unseen imports.
struct MenuBarLabel: View {
    @Environment(RecentStore.self) private var recent

    var body: some View {
        let count = recent.newCount
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
    static let itemLimit = 8

    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(RecentStore.self) private var recent
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, minHeight: 120)
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
            if recent.newCount > 0 {
                Button("Mark All as Seen", systemImage: "checkmark.circle") { recent.markAllSeen() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Mark All as Seen")
            }
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await library.refresh(using: settings) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Refresh")
            .disabled(!settings.isPlexConfigured || library.status == .connecting || recent.isLoading)
        }
        .padding(12)
    }

    @ViewBuilder
    private var content: some View {
        switch library.status {
        case .notConfigured:
            placeholder("Connect to Plex", systemImage: "server.rack", detail: "Add your server and token in Settings.")
        case .failed(let error):
            placeholder(error.localizedDescription, systemImage: "exclamationmark.triangle", detail: error.recoverySuggestion)
        case .connecting, .connected:
            if !recent.hasLoaded {
                ProgressView().controlSize(.small).padding()
            } else if recent.items.isEmpty {
                placeholder("Nothing Here Yet", systemImage: "tray", detail: nil)
            } else {
                TimelineView(.everyMinute) { context in
                    VStack(spacing: 2) {
                        ForEach(recent.items.prefix(Self.itemLimit)) { item in
                            MenuBarRow(item: item, isNew: recent.isNew(item), now: context.date) {
                                show(item)
                            }
                        }
                    }
                    .padding(6)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Curator") { openMainWindow() }
            Spacer()
            SettingsLink { Text("Settings…") }
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
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
                if isNew { NewBadge() }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
