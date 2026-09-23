import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(AppModel.self) private var model
    @State private var isTesting = false

    /// For a Plex server running on a Mac: reads the token from Plex's own settings.
    private static let tokenCommand = "defaults read com.plexapp.plexmediaserver PlexOnlineToken"

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                TextField("Server", text: $settings.serverAddress, prompt: Text("http://my-plex-mac:32400"))
                    .textContentType(.URL)
                if let url = settings.serverURL {
                    if url.absoluteString != settings.serverAddress.trimmed {
                        caption("Connects to \(url.absoluteString)")
                    }
                } else if !settings.serverAddress.trimmed.isEmpty {
                    caption("Enter the computer's name, like my-plex-mac, or a full address like http://192.168.1.20:32400.", color: .red)
                } else {
                    caption("The computer running Plex Media Server. Its name or IP address is enough; Curator adds port 32400.")
                }

                RevealableSecureField(title: "Token", text: $settings.plexToken)
                TokenHelp(plexWebURL: plexWebURL, tokenCommand: Self.tokenCommand)
            } header: {
                Text("Plex Server")
            }

            Section {
                RevealableSecureField(title: "API Key", text: $settings.tmdbKey)
                TMDBHelp()
            } header: {
                Text("Artwork from TMDB (optional)")
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

    /// Plex Web on the configured server, or plex.tv's hosted Plex Web.
    private var plexWebURL: URL {
        settings.serverURL?.appending(path: "web") ?? URL(string: "https://app.plex.tv")!
    }

    private func caption(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Step-by-step help for finding the Plex token, without needing Terminal.
private struct TokenHelp: View {
    let plexWebURL: URL
    let tokenCommand: String

    var body: some View {
        HelpDisclosure("How do I find my token?") {
            VStack(alignment: .leading, spacing: 8) {
                Step(1) {
                    HStack(spacing: 4) {
                        Text("Open Plex in your browser and sign in.")
                        Link("Open Plex Web", destination: plexWebURL)
                    }
                }
                Step(2) { Text("Open any movie, then choose **⋯ → Get Info**.") }
                Step(3) { Text("Click **View XML** at the bottom of the window.") }
                Step(4) { Text("In the new page's address bar, copy the text after **X-Plex-Token=** and paste it above.") }

                Divider()
                Text("If Plex Media Server runs on a Mac, you can also run this in Terminal on that Mac:")
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text(tokenCommand)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(tokenCommand, forType: .string)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Copy command")
                }
            }
            .font(.callout)
            .padding(.top, 4)
        }
    }
}

/// How to get a free TMDB key; artwork works without one.
private struct TMDBHelp: View {
    var body: some View {
        HelpDisclosure("Posters come from Plex without a key. How do I get one?") {
            VStack(alignment: .leading, spacing: 8) {
                Step(1) {
                    HStack(spacing: 4) {
                        Text("Create a free account at")
                        Link("themoviedb.org", destination: URL(string: "https://www.themoviedb.org/signup")!)
                    }
                }
                Step(2) {
                    HStack(spacing: 4) {
                        Text("Open")
                        Link("Settings → API", destination: URL(string: "https://www.themoviedb.org/settings/api")!)
                        Text("and request a Developer key.")
                    }
                }
                Step(3) { Text("Copy the **API Key** (or the longer **API Read Access Token**) and paste it above.") }
            }
            .font(.callout)
            .padding(.top, 4)
        }
    }
}

/// A disclosure whose title is clickable too. A plain `DisclosureGroup` on macOS only
/// toggles from its small triangle, and people click the words.
private struct HelpDisclosure<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @State private var isExpanded = false

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content
        } label: {
            Button(title) {
                withAnimation { isExpanded.toggle() }
            }
            .buttonStyle(.plain)
        }
    }
}

private struct Step<Content: View>: View {
    let number: Int
    @ViewBuilder let content: Content

    init(_ number: Int, @ViewBuilder content: () -> Content) {
        self.number = number
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            content
                .fixedSize(horizontal: false, vertical: true)
        }
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
