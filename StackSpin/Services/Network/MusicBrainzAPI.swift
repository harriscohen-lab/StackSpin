import Foundation

final class MusicBrainzAPI {
    private let session: URLSession
    private let cache = ResponseCache()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func releaseByBarcode(_ upc: String) async throws -> [MBRelease] {
        let key = "barcode-\(upc)"
        if let cached: [MBRelease] = cache.value(forKey: key) {
            return cached
        }
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release")!
        components.queryItems = [
            URLQueryItem(name: "query", value: "barcode:\(upc)"),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "5")
        ]
        let (data, response) = try await session.data(for: URLRequest(url: components.url!))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.network("MusicBrainz barcode lookup failed")
        }
        let payload = try JSONDecoder().decode(MBSearchResponse.self, from: data)
        let models = payload.releases.map { $0.toModel() }
        cache.store(models, forKey: key)
        return models
    }

    func searchRelease(artist: String?, album: String?, catno: String?) async throws -> [MBRelease] {
        var queryComponents: [String] = []
        if let artist, !artist.isEmpty { queryComponents.append("artist:\"\(artist)\"") }
        if let album, !album.isEmpty { queryComponents.append("release:\"\(album)\"") }
        if let catno, !catno.isEmpty { queryComponents.append("catno:\(catno)") }
        guard !queryComponents.isEmpty else { return [] }
        let query = queryComponents.joined(separator: " AND ")
        let key = "search-\(query)"
        if let cached: [MBRelease] = cache.value(forKey: key) {
            return cached
        }
        var components = URLComponents(string: "https://musicbrainz.org/ws/2/release")!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "fmt", value: "json"),
            URLQueryItem(name: "limit", value: "10")
        ]
        let (data, response) = try await session.data(for: URLRequest(url: components.url!))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.network("MusicBrainz search failed")
        }
        let payload = try JSONDecoder().decode(MBSearchResponse.self, from: data)
        let models = payload.releases.map { $0.toModel() }
        cache.store(models, forKey: key)
        return models
    }

    func coverThumbURL(for mbid: String) -> URL? {
        URL(string: "https://coverartarchive.org/release/\(mbid)/front-250")
    }
}

private struct MBSearchResponse: Decodable {
    struct Release: Decodable {
        struct ArtistCredit: Decodable {
            struct Name: Decodable {
                let name: String
            }
            let name: String?
            let artist: Artist?
        }
        struct Artist: Decodable {
            let name: String
        }
        struct LabelInfo: Decodable {
            let label: Label?
        }
        struct Label: Decodable {
            let name: String?
        }

        let id: String
        let title: String
        let date: String?
        let country: String?
        let barcode: String?
        let artistCredit: [ArtistCredit]
        let labelInfo: [LabelInfo]?

        enum CodingKeys: String, CodingKey {
            case id, title, date, country, barcode
            case artistCredit = "artist-credit"
            case labelInfo = "label-info"
        }

        func toModel() -> MBRelease {
            let artistName = artistCredit.first?.artist?.name ?? artistCredit.first?.name ?? ""
            let labelName = labelInfo?.first?.label?.name
            return MBRelease(
                id: id,
                title: title,
                artistCredit: artistName,
                date: date,
                label: labelName,
                barcode: barcode,
                country: country
            )
        }
    }

    let releases: [Release]
}

private final class ResponseCache {
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var store: [String: Data] = [:]

    func value<T: Decodable>(forKey key: String) -> T? {
        guard let data = store[key] else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    func store<T: Encodable>(_ value: T, forKey key: String) {
        store[key] = try? encoder.encode(value)
    }
}
