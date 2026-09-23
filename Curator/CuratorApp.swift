import SwiftUI

@main
struct CuratorApp: App {
    @State private var settings = SettingsStore()
    @State private var library = LibraryStore()
    @State private var tmdb = TMDBStore()
    @State private var artwork = ArtworkLoader()
    @State private var recent = RecentStore()
    @State private var search = SearchStore()
    @State private var navigation = AppNavigation()

    var body: some Scene {
        Window("Curator", id: "main") {
            ContentView()
                .environment(settings)
                .environment(library)
                .environment(tmdb)
                .environment(artwork)
                .environment(recent)
                .environment(search)
                .environment(navigation)
        }
        .defaultSize(width: 1100, height: 750)
        .commands {
            CuratorCommands(settings: settings, library: library)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(settings)
                .environment(library)
                .environment(tmdb)
                .environment(artwork)
                .environment(recent)
                .environment(navigation)
        } label: {
            MenuBarLabel()
                .modifier(BackgroundSync())
                .environment(settings)
                .environment(library)
                .environment(tmdb)
                .environment(recent)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(settings)
                .environment(library)
                .environment(tmdb)
        }
    }
}

private struct CuratorCommands: Commands {
    let settings: SettingsStore
    let library: LibraryStore
    @FocusedValue(\.focusSearch) private var focusSearch

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            Button("Search Library") { focusSearch?() }
                .keyboardShortcut("f")
                .disabled(focusSearch == nil)
            Button("Refresh") {
                Task { await library.refresh(using: settings) }
            }
            .keyboardShortcut("r")
            .disabled(!settings.isPlexConfigured)
            Divider()
        }
    }
}
