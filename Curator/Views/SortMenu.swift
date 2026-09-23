import SwiftUI

/// The toolbar's Sort menu: which field, then the order in words that fit it.
struct SortMenu: View {
    @Binding var sort: LibrarySort

    var body: some View {
        Menu {
            Picker("Sort By", selection: fieldBinding) {
                ForEach(LibrarySort.Field.allCases, id: \.self) { field in
                    Text(field.label).tag(field)
                }
            }
            .pickerStyle(.inline)

            Picker("Order", selection: $sort.ascending) {
                Text(sort.field.orderLabels.ascending).tag(true)
                Text(sort.field.orderLabels.descending).tag(false)
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sorted by \(sort.field.label.lowercased()), \(orderLabel.lowercased())")
    }

    private var orderLabel: String {
        sort.ascending ? sort.field.orderLabels.ascending : sort.field.orderLabels.descending
    }

    /// Picking a field starts with its natural order (A to Z, newest or highest first).
    private var fieldBinding: Binding<LibrarySort.Field> {
        Binding { sort.field } set: { sort = sort.with(field: $0) }
    }
}

/// What a poster's second line shows for a given sort.
enum SortedValue {
    /// The item's subtitle with the value it's sorted by.
    static func subtitle(for item: PlexItem, sortedBy field: LibrarySort.Field) -> String? {
        let year = item.year.map(String.init)
        switch field {
        case .title:
            return item.displaySubtitle
        case .releaseDate:
            return item.releaseDate.map(Format.releaseDate) ?? year
        case .dateAdded:
            return [year, value(for: item, field)].compactMap(\.self).joined(separator: " · ")
        case .rating:
            return [value(for: item, field), year].compactMap(\.self).joined(separator: " · ")
        }
    }

    /// Just the sorted value ("★ 9.2", "added 2d ago", "Jun 16, 1980"); nil for title.
    static func value(for item: PlexItem, _ field: LibrarySort.Field) -> String? {
        switch field {
        case .title: nil
        case .releaseDate: item.releaseDate.map(Format.releaseDate)
        case .dateAdded: item.addedAt.map { "added " + Format.relative($0) }
        case .rating: item.audienceRating.map { String(format: "★ %.1f", $0) }
        }
    }
}
