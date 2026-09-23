import Foundation
import Observation

/// Full metadata for items shown in the inspector, cached by rating key. Listings carry
/// only part of an item, so the inspector asks for the rest here.
@Observable
final class ItemDetailStore {
    private(set) var details: [String: PlexItem] = [:]

    @ObservationIgnored var context: () -> PlexContext? = { nil }
    @ObservationIgnored private var inFlight: [String: Task<Void, Never>] = [:]

    func detail(for ratingKey: String) -> PlexItem? {
        details[ratingKey]
    }

    /// Loads once per item; results are keyed by item, so they can never land on another.
    func load(_ ratingKey: String) {
        guard details[ratingKey] == nil, inFlight[ratingKey] == nil, let client = context()?.client else { return }
        inFlight[ratingKey] = Task { [weak self] in
            let item = try? await client.item(ratingKey: ratingKey)
            guard let self else { return }
            inFlight[ratingKey] = nil
            if let item { details[ratingKey] = item }
        }
    }

    /// After reconnecting (possibly to another server), cached details are stale.
    func removeAll() {
        inFlight.values.forEach { $0.cancel() }
        inFlight = [:]
        details = [:]
    }
}
