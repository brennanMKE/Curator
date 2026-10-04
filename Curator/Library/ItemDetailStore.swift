import Foundation
import Observation

/// Full metadata for items shown in the inspector, cached by rating key. Listings carry
/// only part of an item, so the inspector asks for the rest here.
///
/// Extras are fetched separately and never treated as final: bonus features can be imported
/// after the movie, so they reload each time the item is shown and on every poll while it is.
@Observable
final class ItemDetailStore {
    private(set) var details: [String: PlexItem] = [:]
    private(set) var extras: [String: [PlexItem]] = [:]

    @ObservationIgnored var context: () -> PlexContext? = { nil }
    @ObservationIgnored private var inFlight: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var extrasInFlight: [String: Task<Void, Never>] = [:]
    /// The item the inspector last asked for; the poll keeps its extras current.
    @ObservationIgnored private var shown: String?

    func detail(for ratingKey: String) -> PlexItem? {
        details[ratingKey]
    }

    /// Nil until the first load finishes, so the view can tell "none" from "not yet".
    func extras(for ratingKey: String) -> [PlexItem]? {
        extras[ratingKey]
    }

    /// Loads once per item; results are keyed by item, so they can never land on another.
    func load(_ ratingKey: String) {
        shown = ratingKey
        loadExtras(ratingKey)
        guard details[ratingKey] == nil, inFlight[ratingKey] == nil, let client = context()?.client else { return }
        inFlight[ratingKey] = Task { [weak self] in
            let item = try? await client.item(ratingKey: ratingKey)
            guard let self else { return }
            inFlight[ratingKey] = nil
            if let item { details[ratingKey] = item }
        }
    }

    /// Called by `AppModel`'s poll, so extras appear while an import is running.
    func refreshExtras() {
        if let shown { loadExtras(shown) }
    }

    private func loadExtras(_ ratingKey: String) {
        guard extrasInFlight[ratingKey] == nil, let client = context()?.client else { return }
        extrasInFlight[ratingKey] = Task { [weak self] in
            let items = try? await client.extras(ratingKey: ratingKey)
            guard let self else { return }
            extrasInFlight[ratingKey] = nil
            // A failed refresh keeps what was shown; only a real change notifies.
            if let items, extras[ratingKey] != items { extras[ratingKey] = items }
        }
    }

    /// After reconnecting (possibly to another server), cached details are stale.
    func removeAll() {
        inFlight.values.forEach { $0.cancel() }
        extrasInFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        extrasInFlight = [:]
        details = [:]
        extras = [:]
        shown = nil
    }
}
