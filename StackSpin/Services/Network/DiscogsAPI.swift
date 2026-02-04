import Foundation

final class DiscogsAPI {
    private let session: URLSession
    private let token: String?

    init(token: String? = nil, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    func searchByBarcode(_ upc: String) async throws -> [DGRelease] {
        var components = URLComponents(string: "https://api.discogs.com/database/search")!
        components.queryItems = [
            URLQueryItem(name: "barcode", value: upc),
            URLQueryItem(name: "type", value: "release"),
            URLQueryItem(name: "per_page", value: "5")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("StackSpin/1.0 +https://example.com", forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.network("Discogs search failed")
        }
        let payload = try JSONDecoder().decode(SearchResponse.self, from: data)
        return payload.results.map { item in
            DGRelease(
                id: item.id,
                title: item.title,
                artist: item.artist,
                year: item.year,
                label: item.label.first,
                barcode: item.barcode?.first
            )
        }
    }
}

private struct SearchResponse: Decodable {
    struct Result: Decodable {
        let id: Int
        let title: String
        let year: Int?
        let label: [String]
        let barcode: [String]?
        let type: String

        var artist: String {
            title.split(separator: "-").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? title
        }
    }
    let results: [Result]
}
