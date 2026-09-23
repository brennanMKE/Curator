import SwiftUI

@main
struct CuratorApp: App {
    @State private var settings = SettingsStore()
    @State private var library = LibraryStore()

    var body: some Scene {
        Window("Curator", id: "main") {
            ContentView()
                .environment(settings)
                .environment(library)
        }
        .defaultSize(width: 1000, height: 700)
        .commands {
            CommandGroup(before: .toolbar) {
                Button("Refresh") {
                    Task { await library.refresh(using: settings) }
                }
                .keyboardShortcut("r")
                .disabled(!settings.isPlexConfigured)
                Divider()
            }
        }

        Settings {
            SettingsView()
                .environment(settings)
                .environment(library)
        }
    }
}
