import CoreGraphics
import Foundation
import ImageIO
import Observation
import os

/// Loads posters and backdrops. TMDB is used only while `TMDBStore.isAvailable`; otherwise,
/// or when TMDB has nothing for a title, Plex's own artwork is used.
@Observable
final class ArtworkLoader {
    enum Kind: String, Sendable {
        case poster
        case backdrop

        var maxPixelSize: Int { self == .poster ? 600 : 1600 }
        var plexSize: (width: Int, height: Int) { self == .poster ? (342, 513) : (1280, 720) }
        var tmdbSize: TMDBClient.ImageSize { self == .poster ? .poster : .backdrop }
    }

    @ObservationIgnored private let images = NSCache<NSString, ImageBox>()
    @ObservationIgnored private var inFlight: [String: Task<CGImage?, Never>] = [:]
    @ObservationIgnored private var tmdbPaths: [String: TMDBClient.Images]
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let pathsFile: URL?

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            directory: caches?.appending(path: "Artwork", directoryHint: .isDirectory)
        )
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
        images.countLimit = 400

        pathsFile = caches?.appending(path: "tmdb-images.json")
        tmdbPaths = pathsFile
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: TMDBClient.Images].self, from: $0) } ?? [:]
    }

    func cachedImage(for item: PlexItem, kind: Kind, tmdb: TMDBStore) -> CGImage? {
        images.object(forKey: cacheKey(item, kind, useTMDB: usesTMDB(item, tmdb)) as NSString)?.image
    }

    func image(for item: PlexItem, kind: Kind, plex: PlexClient?, tmdb: TMDBStore) async -> CGImage? {
        let useTMDB = usesTMDB(item, tmdb)
        let key = cacheKey(item, kind, useTMDB: useTMDB)
        if let cached = images.object(forKey: key as NSString) { return cached.image }
        if let pending = inFlight[key] { return await pending.value }

        let task = Task { await load(item, kind: kind, plex: plex, tmdb: useTMDB ? tmdb : nil) }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { images.setObject(ImageBox(image), forKey: key as NSString) }
        return image
    }

    private func usesTMDB(_ item: PlexItem, _ tmdb: TMDBStore) -> Bool {
        tmdb.isAvailable && item.tmdbID != nil && (item.kind == .movie || item.kind == .show)
    }

    private func cacheKey(_ item: PlexItem, _ kind: Kind, useTMDB: Bool) -> String {
        "\(useTMDB ? "tmdb" : "plex")|\(item.ratingKey)|\(kind.rawValue)"
    }

    private func load(_ item: PlexItem, kind: Kind, plex: PlexClient?, tmdb: TMDBStore?) async -> CGImage? {
        if let tmdb, let url = await tmdbURL(for: item, kind: kind, tmdb: tmdb),
           let image = try? await Self.fetch(URLRequest(url: url), session: session, maxPixelSize: kind.maxPixelSize) {
            return image
        }

        guard let plex, let path = kind == .poster ? item.posterPath : item.backdropPath else { return nil }
        let size = kind.plexSize
        let request = plex.imageRequest(path: path, width: size.width, height: size.height)
        return try? await Self.fetch(request, session: session, maxPixelSize: kind.maxPixelSize)
    }

    private func tmdbURL(for item: PlexItem, kind: Kind, tmdb: TMDBStore) async -> URL? {
        guard let id = item.tmdbID, let client = tmdb.client else { return nil }
        let type: TMDBClient.MediaType = item.kind == .show ? .tv : .movie
        let key = "\(type.rawValue)-\(id)"

        let paths: TMDBClient.Images
        if let known = tmdbPaths[key] {
            paths = known
        } else {
            do {
                paths = try await client.images(for: id, type: type)
            } catch TMDBError.rejected {
                tmdb.markRejected()
                return nil
            } catch TMDBError.notFound {
                paths = TMDBClient.Images(posterPath: nil, backdropPath: nil)
            } catch {
                return nil
            }
            tmdbPaths[key] = paths
            scheduleSave()
        }

        let path = kind == .poster ? paths.posterPath : paths.backdropPath
        return path.map { TMDBClient.imageURL(path: $0, size: kind.tmdbSize) }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let pathsFile else { return }
            do {
                try JSONEncoder().encode(tmdbPaths).write(to: pathsFile, options: .atomic)
            } catch {
                Log.tmdb.error("Saving image paths failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Downloads and downsamples off the main actor.
    @concurrent
    private nonisolated static func fetch(_ request: URLRequest, session: URLSession, maxPixelSize: Int) async throws -> CGImage? {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

private final class ImageBox {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}
