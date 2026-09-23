import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @State private var isTesting = false
    @State private var importMessage: String?

    private static let tokenCommand = "ssh joe 'defaults read com.plexapp.plexmediaserver PlexOnlineToken'"

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                TextField("Server", text: $settings.serverAddress, prompt: Text(SettingsStore.defaultServerAddress))
                    .textContentType(.URL)
                if let url = settings.serverURL {
                    if url.absoluteString != settings.serverAddress.trimmed {
                        caption("Connects to \(url.absoluteString)")
                    }
                } else if !settings.serverAddress.trimmed.isEmpty {
                    caption("Enter a host name like joe, or a URL like http://joe:32400.", color: .red)
                }

                RevealableSecureField(title: "Token", text: $settings.plexToken)
                VStack(alignment: .leading, spacing: 4) {
                    caption("Read the token on joe with:")
                    HStack(spacing: 6) {
                        Text(Self.tokenCommand)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Copy", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Self.tokenCommand, forType: .string)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Copy command")
                    }
                }
            } header: {
                Text("Plex Server")
            }

            Section {
                RevealableSecureField(title: "API Key", text: $settings.tmdbKey)
                HStack(spacing: 0) {
                    caption("Optional. Adds TMDB posters and backdrops; without it, artwork comes from Plex. A v3 API key or v4 read access token both work. ")
                    Link("Get a key", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                        .font(.caption)
                }
            } header: {
                Text("TMDB")
            }

            Section {
                HStack {
                    Button("Import .env…") { importEnvFile() }
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([settings.fileURL])
                    }
                    Spacer()
                }
                caption(importMessage ?? "Saved to \(settings.fileURL.path(percentEncoded: false)) using the keys in .env.example.")
            } header: {
                Text("Storage")
            }

            Section {
                PlexStatusRow()
                TMDBStatusRow()
                HStack {
                    Spacer()
                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(!settings.isPlexConfigured || isTesting)
                    .keyboardShortcut(.defaultAction)
                }
            } header: {
                Text("Status")
            }
        }
        .formStyle(.grouped)
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }

        await model.testConnection()
    }

    private func importEnvFile() {
        let panel = NSOpenPanel()
        panel.title = "Import .env"
        panel.message = "Choose a .env file with PLEX_URL, PLEX_TOKEN or TMDB_API_KEY."
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let imported = settings.importValues(from: try EnvFile(contentsOf: url))
            importMessage = imported.isEmpty
                ? "No PLEX_URL, PLEX_TOKEN or TMDB_API_KEY in \(url.lastPathComponent)."
                : "Imported \(imported.joined(separator: ", ")) from \(url.path(percentEncoded: false))."
        } catch {
            importMessage = "Couldn't read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func caption(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PlexStatusRow: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        switch library.status {
        case .notConfigured:
            StatusLabel(title: "Plex", detail: "Add a server address and token.", symbol: "circle.dashed", tint: .secondary)
        case .connecting:
            LabeledContent("Plex") {
                ProgressView().controlSize(.small)
            }
        case .failed(let error):
            StatusLabel(
                title: error.localizedDescription,
                detail: error.recoverySuggestion,
                symbol: "xmark.circle.fill",
                tint: .red
            )
        case .connected:
            VStack(alignment: .leading, spacing: 6) {
                StatusLabel(
                    title: "Connected to \(library.server?.friendlyName ?? "Plex")",
                    detail: library.server.map { "Plex Media Server \($0.shortVersion)" },
                    symbol: "checkmark.circle.fill",
                    tint: .green
                )
                ForEach(library.libraries) { item in
                    LabeledContent {
                        Text(item.itemCount.map(item.section.kind.itemCountLabel) ?? "count unavailable")
                            .monospacedDigit()
                    } label: {
                        Label(item.section.title, systemImage: item.section.kind.systemImage)
                    }
                    .padding(.leading, 24)
                }
            }
        }
    }
}

private struct TMDBStatusRow: View {
    @Environment(TMDBStore.self) private var tmdb

    var body: some View {
        switch tmdb.status {
        case .off:
            StatusLabel(title: "TMDB not set", detail: "Artwork comes from Plex.", symbol: "circle.dashed", tint: .secondary)
        case .checking:
            LabeledContent("TMDB") {
                ProgressView().controlSize(.small)
            }
        case .valid:
            StatusLabel(title: "TMDB key accepted", detail: "Artwork comes from TMDB, with Plex as a fallback.", symbol: "checkmark.circle.fill", tint: .green)
        case .rejected:
            StatusLabel(title: "TMDB rejected the key", detail: "Using artwork from Plex until the key is fixed.", symbol: "xmark.circle.fill", tint: .red)
        case .unreachable(let message):
            StatusLabel(title: message, detail: "Using artwork from Plex.", symbol: "exclamationmark.triangle.fill", tint: .orange)
        }
    }
}

private struct StatusLabel: View {
    let title: String
    let detail: String?
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
    }
}

/// A secure field with an eye button, so a pasted token can be checked by eye.
private struct RevealableSecureField: View {
    let title: String
    @Binding var text: String
    @State private var isRevealed = false

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if isRevealed {
                    TextField(title, text: $text)
                        .fontDesign(.monospaced)
                } else {
                    SecureField(title, text: $text)
                }
            }
            .autocorrectionDisabled()

            Button(isRevealed ? "Hide" : "Show", systemImage: isRevealed ? "eye.slash" : "eye") {
                isRevealed.toggle()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(isRevealed ? "Hide" : "Show")
        }
    }
}
