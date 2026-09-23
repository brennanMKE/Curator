import SwiftUI

/// A poster or backdrop that fills its frame, with a placeholder while loading or when
/// there is no artwork.
struct ArtworkView: View {
    let item: PlexItem
    let kind: ArtworkLoader.Kind

    @Environment(ArtworkLoader.self) private var loader
    @Environment(SettingsStore.self) private var settings
    @Environment(TMDBStore.self) private var tmdb
    @State private var image: CGImage?
    @State private var loadedKey: String?

    var body: some View {
        ZStack {
            placeholder
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            }
        }
        .clipped()
        .task(id: taskKey) {
            if loadedKey?.hasPrefix(item.ratingKey + "|") != true {
                // A different item: don't leave the previous poster showing.
                image = loader.cachedImage(for: item, kind: kind, tmdb: tmdb)
            }
            let loaded = await loader.image(for: item, kind: kind, plex: settings.plexClient, tmdb: tmdb)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.15)) { image = loaded ?? image }
            loadedKey = taskKey
        }
    }

    private var taskKey: String {
        "\(item.ratingKey)|\(kind.rawValue)|\(tmdb.isAvailable)|\(settings.plexConnectionKey.hashValue)"
    }

    private var placeholder: some View {
        Rectangle()
            .fill(.quaternary)
            .overlay {
                Image(systemName: item.kind == .movie ? "film" : "tv")
                    .font(kind == .poster ? .title : .largeTitle)
                    .foregroundStyle(.tertiary)
            }
    }
}
