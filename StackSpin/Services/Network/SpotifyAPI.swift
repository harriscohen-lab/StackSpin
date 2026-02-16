import Foundation

final class SpotifyAPI {
    private let authController: SpotifyAuthController
    private let session: URLSession

    init(authController: SpotifyAuthController, session: URLSession = .shared) {
        self.authController = authController
        self.session = session
    }

    func searchAlbum(artist: String, title: String, market: String) async throws -> SpotifyAlbum? {
        let token = try await authController.withValidToken()
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "type", value: "album"),
            URLQueryItem(name: "q", value: "album:\"\(title)\" artist:\"\(artist)\""),
            URLQueryItem(name: "market", value: market),
            URLQueryItem(name: "limit", value: "1")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.network("Spotify album search failed")
        }
        let result = try JSONDecoder().decode(SpotifySearchResponse.self, from: data)
        guard let album = result.albums.items.first else { return nil }
        return SpotifyAlbum(
            id: album.id,
            name: album.name,
            artist: album.artists.first?.name ?? artist,
            imageURL: URL(string: album.images.first?.url ?? ""),
            uri: album.uri
        )
    }

    func albumTracks(albumID: String) async throws -> [SpotifyTrack] {
        let token = try await authController.withValidToken()
        var components = URLComponents(string: "https://api.spotify.com/v1/albums/\(albumID)/tracks")!
        components.queryItems = [URLQueryItem(name: "limit", value: "50")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.network("Spotify tracks fetch failed")
        }
        let result = try JSONDecoder().decode(SpotifyTracksResponse.self, from: data)
        return result.items.map { item in
            SpotifyTrack(
                id: item.id,
                name: item.name,
                uri: item.uri,
                discNumber: item.discNumber,
                trackNumber: item.trackNumber
            )
        }
    }

    func addTracks(playlistID: String, trackURIs: [String]) async throws {
        guard !trackURIs.isEmpty else { return }
        let token = try await authController.withValidToken()
        try await validatePlaylistWriteAccess(playlistID: playlistID, token: token)

        let chunks = stride(from: 0, to: trackURIs.count, by: 100).map {
            Array(trackURIs[$0..<min($0 + 100, trackURIs.count)])
        }
        for chunk in chunks {
            var success = false
            while !success {
                var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/playlists/\(playlistID)/tracks")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(["uris": chunk])

                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw AppError.network("Spotify add tracks failed")
                }
                if http.statusCode == 429,
                   let retryAfter = http.value(forHTTPHeaderField: "Retry-After"),
                   let delay = Double(retryAfter) {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                guard 200..<300 ~= http.statusCode else {
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    if http.statusCode == 403 {
                        throw AppError.network(
                            "Spotify add tracks failed (403 Forbidden). Make sure the selected playlist belongs to the signed-in account or is collaborative, then reconnect Spotify and try again. Response: \(message)"
                        )
                    }
                    throw AppError.network("Spotify add tracks failed: \(message)")
                }
                success = true
            }
        }
    }

    private func validatePlaylistWriteAccess(playlistID: String, token: String) async throws {
        let profile = try await currentUserProfile(token: token)
        let playlist = try await playlistMetadata(playlistID: playlistID, token: token)

        guard playlist.isWritable(byUserID: profile.id) else {
            throw AppError.network(
                "Spotify playlist is not writable by the current account. Signed in as @\(profile.id), playlist owner is @\(playlist.owner.id). Select a playlist you own or a collaborative playlist."
            )
        }
    }

    private func currentUserProfile(token: String) async throws -> SpotifyCurrentUser {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AppError.network("Spotify profile fetch failed: \(message)")
        }
        return try JSONDecoder().decode(SpotifyCurrentUser.self, from: data)
    }

    private func playlistMetadata(playlistID: String, token: String) async throws -> SpotifyPlaylistMetadata {
        var components = URLComponents(string: "https://api.spotify.com/v1/playlists/\(playlistID)")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "id,collaborative,owner(id)")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AppError.network("Spotify playlist lookup failed: \(message)")
        }
        return try JSONDecoder().decode(SpotifyPlaylistMetadata.self, from: data)
    }
}

private struct SpotifySearchResponse: Decodable {
    struct Albums: Decodable {
        struct Album: Decodable {
            struct Artist: Decodable {
                let name: String
            }
            struct Image: Decodable {
                let url: String
            }
            let id: String
            let name: String
            let uri: String
            let artists: [Artist]
            let images: [Image]
        }
        let items: [Album]
    }
    let albums: Albums
}

private struct SpotifyCurrentUser: Decodable {
    let id: String
}

private struct SpotifyPlaylistMetadata: Decodable {
    struct Owner: Decodable {
        let id: String
    }

    let id: String
    let collaborative: Bool
    let owner: Owner

    func isWritable(byUserID userID: String) -> Bool {
        collaborative || owner.id == userID
    }
}

private struct SpotifyTracksResponse: Decodable {
    struct Item: Decodable {
        let id: String
        let name: String
        let uri: String
        let discNumber: Int
        let trackNumber: Int

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case uri
            case discNumber = "disc_number"
            case trackNumber = "track_number"
        }
    }
    let items: [Item]
}
