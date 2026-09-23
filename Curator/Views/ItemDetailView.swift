import SwiftUI

/// The inspector: artwork, what the title is, and where its file lives — the part that
/// matters when checking an import.
struct ItemDetailView: View {
    let item: PlexItem

    @Environment(SettingsStore.self) private var settings
    @Environment(LibraryStore.self) private var library
    @Environment(\.openURL) private var openURL
    @State private var detail: PlexItem?

    /// Listings and hub results carry partial metadata; the full record fills in when loaded.
    private var shown: PlexItem { detail ?? item }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Color.clear
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay { ArtworkView(item: shown, kind: .backdrop) }
                    .clipShape(.rect(cornerRadius: 8))

                header

                if let url = webURL {
                    Button("Open in Plex", systemImage: "play.rectangle.fill") { openURL(url) }
                        .buttonStyle(.borderedProminent)
                }

                if let summary = shown.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                facts
            }
            .padding(16)
        }
        .task(id: item.id) {
            detail = nil
            guard let client = settings.plexClient else { return }
            detail = try? await client.item(ratingKey: item.ratingKey)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shown.displayTitle)
                .font(.title2.bold())
                .textSelection(.enabled)
            if shown.kind == .episode, let subtitle = shown.displaySubtitle {
                Text(subtitle).font(.headline)
            }
            let meta = [
                shown.kind == .episode ? nil : shown.year.map(String.init),
                shown.duration.map { Format.runtime(milliseconds: $0) },
                shown.contentRating,
                shown.audienceRating.map { String(format: "★ %.1f", $0) },
            ].compactMap(\.self)
            if !meta.isEmpty {
                Text(meta.joined(separator: " · "))
                    .foregroundStyle(.secondary)
            }
            if let tagline = shown.tagline, !tagline.isEmpty {
                Text(tagline)
                    .italic()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var facts: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
            if let added = shown.addedAt {
                row("Added", "\(added.formatted(date: .abbreviated, time: .shortened)) (\(Format.relative(added)))")
            }
            if !shown.genres.isEmpty { row("Genre", shown.genres.joined(separator: ", ")) }
            if !shown.directors.isEmpty { row("Director", shown.directors.joined(separator: ", ")) }
            if !shown.cast.isEmpty { row("Cast", shown.cast.prefix(6).joined(separator: ", ")) }
            if let media = shown.media.first {
                let summary = Format.mediaSummary(media)
                if !summary.isEmpty { row("Video", summary) }
                if let part = media.parts.first {
                    if let file = part.file {
                        GridRow {
                            label("File")
                            Text(file)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let size = part.size { row("Size", Format.fileSize(size)) }
                }
            } else if detail == nil {
                GridRow {
                    label("File")
                    ProgressView().controlSize(.small)
                }
            }
        }
        .font(.callout)
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            label(title)
            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private var webURL: URL? {
        guard let server = library.server else { return nil }
        return settings.plexClient?.webURL(for: shown, machineIdentifier: server.machineIdentifier)
    }
}
