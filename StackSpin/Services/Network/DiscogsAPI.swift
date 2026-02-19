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

        private enum CodingKeys: String, CodingKey {
            case id, title, year, label, barcode, type
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)

            if let labels = try? container.decode([String].self, forKey: .label) {
                label = labels
            } else if let singleLabel = try? container.decode(String.self, forKey: .label) {
                label = [singleLabel]
            } else {
                label = []
            }

            barcode = try container.decodeIfPresent([String].self, forKey: .barcode)
            type = try container.decode(String.self, forKey: .type)

            if let intYear = try? container.decodeIfPresent(Int.self, forKey: .year) {
                year = intYear
            } else if let stringYear = try? container.decodeIfPresent(String.self, forKey: .year) {
                let digits = stringYear.filter(\.isNumber)
                year = Int(digits)
            } else {
                year = nil
            }
        }

        var artist: String {
            title.split(separator: "-").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? title
        }
    }
    let results: [Result]
}
