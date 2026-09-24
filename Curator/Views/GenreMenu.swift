import SwiftUI

/// The toolbar's Genre menu: All Genres, then each genre Plex found in the library, with its
/// count. The icon fills while a genre is chosen.
struct GenreMenu: View {
    let genres: [PlexGenre]
    let counts: [String: Int]
    @Binding var genre: PlexGenre?

    var body: some View {
        Menu {
            Picker("Genre", selection: $genre) {
                Text("All Genres").tag(PlexGenre?.none)
                Divider()
                ForEach(shown) { genre in
                    Text(label(for: genre)).tag(Optional(genre))
                }
            }
            .pickerStyle(.inline)
            if genres.isEmpty {
                Text("No genres yet")
            }
        } label: {
            Label("Genre", systemImage: genre == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        // Without this, VoiceOver and UI tests see the symbol's name.
        .accessibilityLabel("Genre")
        .accessibilityIdentifier("genreMenu")
        .help(genre.map { "Showing \($0.title) only" } ?? "Show one genre")
    }

    /// Genres Plex lists but no title has any more are left out once counted.
    private var shown: [PlexGenre] {
        genres.filter { counts[$0.key] != 0 }
    }

    private func label(for genre: PlexGenre) -> String {
        counts[genre.key].map { "\(genre.title) (\($0))" } ?? genre.title
    }
}
