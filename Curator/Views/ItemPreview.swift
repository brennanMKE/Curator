import SwiftUI

/// A Quick Look–style preview: Space opens it, Space or Escape closes it.
struct ItemPreview: View {
    let item: PlexItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.itemActions) private var actions

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Color.clear
                .frame(width: 220, height: 330)
                .overlay { ArtworkView(item: item, kind: .poster) }
                .clipShape(.rect(cornerRadius: 10))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 10) {
                Text(item.displayTitle)
                    .font(.largeTitle.bold())
                    .lineLimit(2)
                if let subtitle = meta {
                    Text(subtitle).foregroundStyle(.secondary)
                }
                if let tagline = item.tagline, !tagline.isEmpty {
                    Text(tagline).italic().foregroundStyle(.secondary)
                }
                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .lineLimit(8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let added = item.addedAt {
                    Text("Added \(added.formatted(date: .abbreviated, time: .shortened)) (\(Format.relative(added)))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                HStack {
                    Button("Open in Plex", systemImage: "play.rectangle.fill") {
                        dismiss()
                        actions.open(item)
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(24)
        .frame(width: 680, height: 380)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            dismiss()
            return .handled
        }
    }

    private var meta: String? {
        let parts = [
            item.displaySubtitle,
            item.duration.map { Format.runtime(milliseconds: $0) },
            item.contentRating,
            item.media.first.map(Format.mediaSummary),
        ].compactMap(\.self).filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
