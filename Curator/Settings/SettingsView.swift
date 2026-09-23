import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @State private var tmdbStatus: TMDBStatus = .untested
    @State private var isTesting = false

    private static let tokenCommand = "ssh joe 'defaults read com.plexapp.plexmediaserver PlexOnlineToken'"

    enum TMDBStatus: Equatable {
        case untested, checking, accepted
        case failed(String)
    }

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
                    caption("Used for posters and backdrops. A v3 API key or v4 read access token both work. ")
                    Link("Get a key", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                        .font(.caption)
                }
            } header: {
                Text("TMDB")
            }

            Section {
                PlexStatusRow()
                if settings.tmdbClient != nil {
                    TMDBStatusRow(status: tmdbStatus)
                }
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
        .onChange(of: settings.tmdbKey) { tmdbStatus = .untested }
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }

        async let plex: Void = library.refresh(using: settings)
        if let tmdb = settings.tmdbClient {
            tmdbStatus = .checking
            do {
                try await tmdb.validate()
                tmdbStatus = .accepted
            } catch {
                tmdbStatus = .failed(error.localizedDescription)
            }
        }
        await plex
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
    let status: SettingsView.TMDBStatus

    var body: some View {
        switch status {
        case .untested:
            StatusLabel(title: "TMDB", detail: "Not tested yet.", symbol: "circle.dashed", tint: .secondary)
        case .checking:
            LabeledContent("TMDB") {
                ProgressView().controlSize(.small)
            }
        case .accepted:
            StatusLabel(title: "TMDB key accepted", detail: nil, symbol: "checkmark.circle.fill", tint: .green)
        case .failed(let message):
            StatusLabel(title: message, detail: nil, symbol: "xmark.circle.fill", tint: .red)
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
