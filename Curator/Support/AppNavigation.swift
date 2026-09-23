import Observation

/// Cross-scene requests, e.g. the menu bar asking the main window to show an item.
@Observable
final class AppNavigation {
    var pendingItem: PlexItem?
}
