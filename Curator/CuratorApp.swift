import SwiftUI

@main
struct CuratorApp: App {
    @State private var model = AppModel.forLaunch()
    @State private var artwork = ArtworkLoader()
    @State private var navigation = AppNavigation()
    @State private var updater = UpdaterController()

    var body: some Scene {
        Window("Curator", id: "main") {
            ContentView()
                .environment(model)
                .environment(model.settings)
                .environment(model.library)
                .environment(model.tmdb)
                .environment(model.recent)
                .environment(model.search)
                .environment(model.details)
                .environment(artwork)
                .environment(navigation)
        }
        .defaultSize(width: 1100, height: 750)
        .commands {
            CuratorCommands(model: model, updater: updater)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(model)
                .environment(model.settings)
                .environment(model.library)
                .environment(model.tmdb)
                .environment(model.recent)
                .environment(artwork)
                .environment(navigation)
        } label: {
            MenuBarLabel()
                .environment(model.recent)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
                .environment(model.settings)
                .environment(model.library)
                .environment(model.tmdb)
        }
    }
}

private struct CuratorCommands: Commands {
    let model: AppModel
    let updater: UpdaterController
    @FocusedValue(\.focusSearch) private var focusSearch

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            if updater.isConfigured {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
        }
        CommandGroup(before: .toolbar) {
            Button("Search Library") { focusSearch?() }
                .keyboardShortcut("f")
                .disabled(focusSearch == nil)
            Button("Refresh") { model.refresh() }
                .keyboardShortcut("r")
                .disabled(!model.settings.isPlexConfigured)
            Divider()
        }
    }
}
