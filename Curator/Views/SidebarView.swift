import SwiftUI

struct SidebarView: View {
    @Environment(LibraryStore.self) private var library
    @Binding var selection: SidebarItem?

    var body: some View {
        List(selection: $selection) {
            Label("Recently Added", systemImage: "clock")
                .tag(SidebarItem.recentlyAdded)

            if !library.libraries.isEmpty {
                Section("Libraries") {
                    ForEach(library.libraries) { item in
                        Label(item.section.title, systemImage: item.section.kind.systemImage)
                            .badge(item.itemCount ?? 0)
                            .tag(SidebarItem.library(item.id))
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            ConnectionStatusView()
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }
}

/// A one-line indicator of the Plex connection, shown under the sidebar.
struct ConnectionStatusView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        HStack(spacing: 6) {
            switch library.status {
            case .notConfigured:
                indicator(.secondary)
                Text("Not connected")
            case .connecting:
                ProgressView().controlSize(.mini)
                Text("Connecting…")
            case .connected:
                indicator(.green)
                Text(library.server?.friendlyName ?? "Connected")
                    .lineLimit(1)
                    .truncationMode(.middle)
            case .failed:
                indicator(.red)
                Text("Connection failed")
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(helpText)
    }

    private func indicator(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 7, height: 7)
    }

    private var helpText: String {
        switch library.status {
        case .connected:
            guard let server = library.server else { return "" }
            return "Plex Media Server \(server.shortVersion)"
        case .failed(let error):
            return error.localizedDescription
        default:
            return ""
        }
    }
}
