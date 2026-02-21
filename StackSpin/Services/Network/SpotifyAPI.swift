import Foundation
import os

private enum AddTracksForbiddenClassification: String {
    case ownershipMismatch = "ownership_mismatch"
    case permissionsOrScope = "permissions_or_scope"
    case unknownForbidden = "unknown_forbidden"
}

final class SpotifyAPI {
    private let authController: SpotifyAuthController
    private let session: URLSession
    private let onMissingWriteScopes: ((Set<String>) -> Void)?
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "StackSpin",
        category: "SpotifyAPI"
    )

    init(
        authController: SpotifyAuthController,
        session: URLSession = .shared,
        onMissingWriteScopes: ((Set<String>) -> Void)? = nil
    ) {
        self.authController = authController
        self.session = session
        self.onMissingWriteScopes = onMissingWriteScopes
    }

    func searchAlbum(artist: String, title: String, market: String) async throws -> SpotifyAlbum? {
        let token: String
        do {
            token = try await authController.withValidToken()
        } catch {
            logger.error("Spotify dependency failed endpoint=searchAlbum dependency=authToken error=\(String(describing: error), privacy: .public)")
            throw AppError.network("Spotify album search token dependency failed: \(error.localizedDescription)")
        }
        var lastFailure: String?
        let searchQueries = Self.searchQueryCandidates(artist: artist, title: title)

        for query in searchQueries {
            var components = URLComponents(string: "https://api.spotify.com/v1/search")!
            components.queryItems = [
                URLQueryItem(name: "type", value: "album"),
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "market", value: market),
                URLQueryItem(name: "limit", value: "1")
            ]
            var request = URLRequest(url: components.url!)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, http) = try await executeRequest(request, endpoint: "searchAlbum")
            if http.statusCode == 200 {
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

            let body = Self.responseSnippet(from: data)
            lastFailure = "Spotify album search failed (status \(http.statusCode)): \(body)"
            logger.error(
                "Spotify HTTP failure endpoint=searchAlbum status=\(http.statusCode, privacy: .public) body=\(body, privacy: .public) queryLength=\(query.count, privacy: .public)"
            )

            if http.statusCode == 400,
               body.localizedCaseInsensitiveContains("Query exceeds maximum length") {
                continue
            }

            throw AppError.network(lastFailure ?? "Spotify album search failed")
        }

        throw AppError.network(lastFailure ?? "Spotify album search failed")
    }

    func albumTracks(albumID: String) async throws -> [SpotifyTrack] {
        let token: String
        do {
            token = try await authController.withValidToken()
        } catch {
            logger.error("Spotify dependency failed endpoint=albumTracks dependency=authToken error=\(String(describing: error), privacy: .public)")
            throw AppError.network("Spotify tracks lookup token dependency failed: \(error.localizedDescription)")
        }
        var components = URLComponents(string: "https://api.spotify.com/v1/albums/\(albumID)/tracks")!
        components.queryItems = [URLQueryItem(name: "limit", value: "50")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await executeRequest(request, endpoint: "albumTracks")
        guard http.statusCode == 200 else {
            logger.error(
                "Spotify HTTP failure endpoint=albumTracks status=\(http.statusCode, privacy: .public) body=\(Self.responseSnippet(from: data), privacy: .public)"
            )
            throw AppError.network("Spotify tracks fetch failed (status \(http.statusCode)): \(Self.responseSnippet(from: data))")
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
        guard let normalizedPlaylistID = AppSettings.normalizedPlaylistID(from: playlistID),
              normalizedPlaylistID == playlistID.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedPlaylistID.isEmpty else {
            throw AppError.network(
                "Spotify playlist selection is stale or invalid. Reconnect Spotify and reselect a writable playlist."
            )
        }

        var token: String
        do {
            token = try await authController.withValidToken()
        } catch {
            logger.error("Spotify dependency failed endpoint=addTracks dependency=authToken error=\(String(describing: error), privacy: .public)")
            throw AppError.network("Spotify add tracks token dependency failed: \(error.localizedDescription)")
        }
        var writeContext = try await validatePlaylistWriteAccess(playlistID: normalizedPlaylistID, token: token)
        logger.debug(
            "Spotify addTracks writeContext playlistID=\(writeContext.playlistID, privacy: .public) signedInUser=\(writeContext.signedInUserID, privacy: .public) ownerID=\(writeContext.ownerID, privacy: .public) collaborative=\(writeContext.collaborative, privacy: .public) ownershipMatch=\(writeContext.ownershipMatches, privacy: .public) public=\(writeContext.isPublic, privacy: .public) requiredScopes=\(writeContext.requiredWriteScopes.sorted().joined(separator: ","), privacy: .public) tokenDiagnostics=\(self.authController.tokenDiagnostics, privacy: .public)"
        )

        try preflightAddTracksScopeCheck(writeContext: writeContext)

        let chunks = stride(from: 0, to: trackURIs.count, by: 100).map {
            Array(trackURIs[$0..<min($0 + 100, trackURIs.count)])
        }
        for chunk in chunks {
            var success = false
            var hasRetriedAfterRefresh = false
            while !success {
                var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/playlists/\(normalizedPlaylistID)/tracks")!)
                request.httpMethod = "POST"
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(["uris": chunk])

                let (data, http) = try await executeRequest(request, endpoint: "addTracks")
                Self.logScopeHeaders(from: http, logger: logger, endpoint: "addTracks")
                if http.statusCode == 429,
                   let retryAfter = http.value(forHTTPHeaderField: "Retry-After"),
                   let delay = Double(retryAfter) {
                    logger.error(
                        "Spotify request throttled endpoint=addTracks status=429 retryAfter=\(delay, privacy: .public)"
                    )
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                guard 200..<300 ~= http.statusCode else {
                    let bodySnippet = Self.responseSnippet(from: data)
                    logger.error(
                        "Spotify request failed endpoint=addTracks status=\(http.statusCode, privacy: .public) body=\(bodySnippet, privacy: .public)"
                    )
                    if http.statusCode == 403 {
                        let spotifyError = Self.spotifyAPIError(from: data)
                        let classification = Self.classifyAddTracksForbidden(
                            message: spotifyError?.message,
                            ownershipMatch: writeContext.ownershipMatches,
                            collaborative: writeContext.collaborative
                        )
                        logger.error(
                            "Spotify addTracks forbidden signedInUser=\(writeContext.signedInUserID, privacy: .public) playlistID=\(writeContext.playlistID, privacy: .public) ownerID=\(writeContext.ownerID, privacy: .public) collaborative=\(writeContext.collaborative, privacy: .public) ownershipMatch=\(writeContext.ownershipMatches, privacy: .public) classification=\(classification.rawValue, privacy: .public) spotifyStatus=\(spotifyError?.status ?? -1, privacy: .public) spotifyMessage=\(spotifyError?.message ?? "<missing>", privacy: .public) grantedScopes=\(self.authController.grantedScopes.sorted().joined(separator: ","), privacy: .public) requiredScopes=\(writeContext.requiredWriteScopes.sorted().joined(separator: ","), privacy: .public) reconsentPromptedThisSession=\(self.authController.hasPromptedScopeReconsentThisSession, privacy: .public) bodySnippet=\(bodySnippet, privacy: .public)"
                        )

                        if !hasRetriedAfterRefresh {
                            hasRetriedAfterRefresh = true
                            do {
                                token = try await authController.forceRefreshToken()
                                writeContext = try await validatePlaylistWriteAccess(playlistID: normalizedPlaylistID, token: token)
                                try preflightAddTracksScopeCheck(writeContext: writeContext)
                                logger.debug(
                                    "Spotify addTracks retrying after forced refresh playlistID=\(normalizedPlaylistID, privacy: .public) tokenDiagnostics=\(self.authController.tokenDiagnostics, privacy: .public)"
                                )
                                continue
                            } catch {
                                logger.error("Spotify addTracks forced refresh failed playlistID=\(normalizedPlaylistID, privacy: .public) error=\(String(describing: error), privacy: .public)")
                            }
                        }

                        switch classification {
                        case .ownershipMismatch:
                            throw AppError.network(
                                "Spotify add tracks failed (403 Forbidden). Signed in as @\(writeContext.signedInUserID); playlist owned by @\(writeContext.ownerID); collaborative=\(writeContext.collaborative). Reconnect Spotify and reselect a writable playlist."
                            )
                        case .permissionsOrScope, .unknownForbidden:
                            let missingWriteScopes = missingWriteScopesForForbiddenAddTracks(
                                writeContext: writeContext,
                                response: http
                            )
                            if !missingWriteScopes.isEmpty {
                                authController.markScopeReconsentRequired(missingScopes: missingWriteScopes)
                                onMissingWriteScopes?(missingWriteScopes)
                            }
                            throw AppError.spotifyPermissionsExpiredOrInsufficient
                        }
                    }
                    throw AppError.network("Spotify add tracks failed")
                }
                success = true
            }
        }
    }


    func probePlaylistWriteAccess(playlistID: String) async throws -> PlaylistWriteProbeResult {
        guard let normalizedPlaylistID = AppSettings.normalizedPlaylistID(from: playlistID),
              !normalizedPlaylistID.isEmpty else {
            return PlaylistWriteProbeResult(
                playlistID: playlistID,
                ownershipOrCollaborativeAccess: false,
                missingWriteScopes: [],
                hasRequiredWriteScopes: false,
                details: "Playlist ID is invalid."
            )
        }

        let token = try await authController.withValidToken()
        let context = try await playlistWriteContext(playlistID: normalizedPlaylistID, token: token)
        let hasOwnershipAccess = context.collaborative || context.ownershipMatches

        guard hasOwnershipAccess else {
            return PlaylistWriteProbeResult(
                playlistID: context.playlistID,
                ownershipOrCollaborativeAccess: false,
                missingWriteScopes: [],
                hasRequiredWriteScopes: false,
                details: "Signed in as @\(context.signedInUserID), owner @\(context.ownerID), collaborative=\(context.collaborative). Playlist is not writable by this account."
            )
        }

        let missingScopes = missingWriteScopes(writeContext: context)
        if !missingScopes.isEmpty {
            return PlaylistWriteProbeResult(
                playlistID: context.playlistID,
                ownershipOrCollaborativeAccess: true,
                missingWriteScopes: missingScopes,
                hasRequiredWriteScopes: false,
                details: "Signed in as @\(context.signedInUserID), owner @\(context.ownerID), collaborative=\(context.collaborative). Missing required Spotify scope(s): \(missingScopes.sorted().joined(separator: ", ")). Reconnect Spotify and approve these permissions."
            )
        }

        return PlaylistWriteProbeResult(
            playlistID: context.playlistID,
            ownershipOrCollaborativeAccess: true,
            missingWriteScopes: [],
            hasRequiredWriteScopes: true,
            details: "Signed in as @\(context.signedInUserID), owner @\(context.ownerID), collaborative=\(context.collaborative)."
        )
    }

    private func playlistWriteContext(playlistID: String, token: String) async throws -> PlaylistWriteContext {
        let profile = try await currentUserProfile(token: token)
        let playlist = try await playlistMetadata(playlistID: playlistID, token: token)
        let context = PlaylistWriteContext(
            signedInUserID: profile.id,
            playlistID: playlistID,
            ownerID: playlist.owner.id,
            collaborative: playlist.collaborative,
            ownershipMatches: profile.id == playlist.owner.id,
            isPublic: playlist.publicVisibility ?? false
        )
        logger.debug(
            "Spotify playlist write validation playlistID=\(context.playlistID, privacy: .public) signedInUser=\(context.signedInUserID, privacy: .public) ownerID=\(context.ownerID, privacy: .public) collaborative=\(context.collaborative, privacy: .public) ownershipMatch=\(context.ownershipMatches, privacy: .public)"
        )
        return context
    }

    private func validatePlaylistWriteAccess(playlistID: String, token: String) async throws -> PlaylistWriteContext {
        guard let normalizedPlaylistID = AppSettings.normalizedPlaylistID(from: playlistID),
              normalizedPlaylistID == playlistID.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedPlaylistID.isEmpty else {
            throw AppError.network(
                "Spotify playlist selection is stale or invalid. Reconnect Spotify and reselect a writable playlist."
            )
        }

        let context = try await playlistWriteContext(playlistID: normalizedPlaylistID, token: token)

        guard context.collaborative || context.ownershipMatches else {
            throw AppError.network(
                "Spotify playlist is not writable by the current account. Signed in as @\(context.signedInUserID); playlist owned by @\(context.ownerID); collaborative=\(context.collaborative). Reconnect Spotify and reselect a writable playlist."
            )
        }

        return context
    }


    private func preflightAddTracksScopeCheck(writeContext: PlaylistWriteContext) throws {
        let grantedScopes = authController.grantedScopes
        if grantedScopes.isEmpty {
            logger.error(
                "Spotify addTracks preflight skipped playlistID=\(writeContext.playlistID, privacy: .public) reason=unknownGrantedScopes tokenDiagnostics=\(self.authController.tokenDiagnostics, privacy: .public)"
            )
            return
        }
        let missingScopes = missingWriteScopes(writeContext: writeContext)
        guard !missingScopes.isEmpty else { return }

        authController.markScopeReconsentRequired(missingScopes: missingScopes)
        onMissingWriteScopes?(missingScopes)
        logger.error(
            "Spotify addTracks blocked preflight playlistID=\(writeContext.playlistID, privacy: .public) public=\(writeContext.isPublic, privacy: .public) missingScopes=\(missingScopes.sorted().joined(separator: ","), privacy: .public) grantedScopes=\(grantedScopes.sorted().joined(separator: ","), privacy: .public) requiredScopes=\(writeContext.requiredWriteScopes.sorted().joined(separator: ","), privacy: .public)"
        )

        let scopeText = missingScopes.sorted().joined(separator: ", ")
        throw AppError.network(
            "Spotify write permission is missing required scope(s): \(scopeText). Reconnect Spotify to approve these permissions; StackSpin will force Spotify's consent dialog."
        )
    }

    private func missingWriteScopes(writeContext: PlaylistWriteContext) -> Set<String> {
        writeContext.requiredWriteScopes.subtracting(authController.grantedScopes)
    }

    private func currentUserProfile(token: String) async throws -> SpotifyCurrentUser {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await executeRequest(request, endpoint: "currentUserProfile")
        guard http.statusCode == 200 else {
            logger.error(
                "Spotify HTTP failure endpoint=currentUserProfile status=\(http.statusCode, privacy: .public) body=\(Self.responseSnippet(from: data), privacy: .public)"
            )
            throw AppError.network("Spotify profile fetch failed (status \(http.statusCode)): \(Self.responseSnippet(from: data))")
        }
        return try JSONDecoder().decode(SpotifyCurrentUser.self, from: data)
    }

    private func playlistMetadata(playlistID: String, token: String) async throws -> SpotifyPlaylistMetadata {
        var components = URLComponents(string: "https://api.spotify.com/v1/playlists/\(playlistID)")!
        components.queryItems = [
            URLQueryItem(name: "fields", value: "id,collaborative,public,owner(id)")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await executeRequest(request, endpoint: "playlistMetadata")
        guard http.statusCode == 200 else {
            logger.error(
                "Spotify HTTP failure endpoint=playlistMetadata status=\(http.statusCode, privacy: .public) body=\(Self.responseSnippet(from: data), privacy: .public)"
            )
            throw AppError.network("Spotify playlist lookup failed (status \(http.statusCode)): \(Self.responseSnippet(from: data))")
        }
        return try JSONDecoder().decode(SpotifyPlaylistMetadata.self, from: data)
    }

    private func executeRequest(_ request: URLRequest, endpoint: String) async throws -> (Data, HTTPURLResponse) {
        logger.debug(
            "Spotify request start endpoint=\(endpoint, privacy: .public) method=\((request.httpMethod ?? "GET"), privacy: .public) url=\((request.url?.absoluteString ?? "<nil>"), privacy: .public)"
        )
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                logger.error("Spotify request failed endpoint=\(endpoint, privacy: .public) reason=nonHTTPResponse")
                throw AppError.network("Spotify request failed for \(endpoint): non-HTTP response")
            }
            return (data, http)
        } catch let urlError as URLError {
            logger.error(
                "Spotify transport error endpoint=\(endpoint, privacy: .public) domain=\(NSURLErrorDomain, privacy: .public) code=\(urlError.code.rawValue, privacy: .public) message=\(urlError.localizedDescription, privacy: .public)"
            )
            throw AppError.network(
                "Spotify transport failed for \(endpoint) [\(NSURLErrorDomain):\(urlError.code.rawValue)] \(urlError.localizedDescription)"
            )
        } catch {
            logger.error("Spotify request failed endpoint=\(endpoint, privacy: .public) reason=unexpectedError error=\(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private static func responseSnippet(from data: Data, maxLength: Int = 500) -> String {
        guard !data.isEmpty else { return "<empty>" }
        let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        if body.count > maxLength {
            return String(body.prefix(maxLength)) + "…"
        }
        return body
    }

    private static func searchQueryCandidates(artist: String, title: String, limit: Int = 250) -> [String] {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = "album:\"\(normalizedTitle)\" artist:\"\(normalizedArtist)\""
        let albumOnly = "album:\"\(normalizedTitle)\""
        let titleArtist = "\(normalizedTitle) \(normalizedArtist)"
        let titleOnly = normalizedTitle

        var candidates: [String] = []
        var seen = Set<String>()
        for candidate in [preferred, albumOnly, titleArtist, titleOnly] where !candidate.isEmpty {
            let truncatedCandidate = Self.truncated(candidate, maxCharacters: limit)
            if seen.insert(truncatedCandidate).inserted {
                candidates.append(truncatedCandidate)
            }
        }
        return candidates
    }

    private static func truncated(_ value: String, maxCharacters: Int) -> String {
        guard value.count > maxCharacters else { return value }
        return String(value.prefix(maxCharacters))
    }


    private static func classifyAddTracksForbidden(message: String?, ownershipMatch: Bool, collaborative: Bool) -> AddTracksForbiddenClassification {
        guard ownershipMatch || collaborative else {
            return .ownershipMismatch
        }

        let normalizedMessage = (message ?? "").lowercased()
        if normalizedMessage.contains("insufficient") ||
            normalizedMessage.contains("scope") ||
            normalizedMessage.contains("permission") ||
            normalizedMessage.contains("forbidden") {
            return .permissionsOrScope
        }

        return .unknownForbidden
    }

    private static func logScopeHeaders(from response: HTTPURLResponse, logger: Logger, endpoint: String) {
        let parsedHeaders = parsedScopeHeaders(from: response)
        let scope = parsedHeaders.scopeHeader.isEmpty ? nil : parsedHeaders.scopeHeader.sorted().joined(separator: " ")
        let oauthScope = parsedHeaders.oauthScopeHeader.isEmpty ? nil : parsedHeaders.oauthScopeHeader.sorted().joined(separator: " ")
        let acceptedScope = parsedHeaders.acceptedScopeHeader.isEmpty ? nil : parsedHeaders.acceptedScopeHeader.sorted().joined(separator: " ")

        if scope != nil || oauthScope != nil || acceptedScope != nil {
            logger.debug(
                "Spotify response auth headers endpoint=\(endpoint, privacy: .public) scope=\(String(describing: scope ?? "<missing>"), privacy: .public) oauthScopes=\(String(describing: oauthScope ?? "<missing>"), privacy: .public) acceptedScopes=\(String(describing: acceptedScope ?? "<missing>"), privacy: .public)"
            )
        }
    }

    private func missingWriteScopesForForbiddenAddTracks(
        writeContext: PlaylistWriteContext,
        response: HTTPURLResponse
    ) -> Set<String> {
        let requiredWriteScopes = writeContext.requiredWriteScopes
        let diagnosticsGrantedScopes = Self.scopesFromTokenDiagnostics(authController.tokenDiagnostics)
        let knownGrantedScopes = authController.grantedScopes.union(diagnosticsGrantedScopes)
        let headerScopes = Self.parsedScopeHeaders(from: response)

        if headerScopes.hasAnyScopeHeaders {
            let grantedFromHeaders = headerScopes.scopeHeader.union(headerScopes.oauthScopeHeader)
            let requiredFromHeaders = headerScopes.acceptedScopeHeader.isEmpty
                ? requiredWriteScopes
                : requiredWriteScopes.intersection(headerScopes.acceptedScopeHeader)
            let effectiveRequiredScopes = requiredFromHeaders.isEmpty ? requiredWriteScopes : requiredFromHeaders
            let effectiveGrantedScopes = grantedFromHeaders.isEmpty ? knownGrantedScopes : grantedFromHeaders
            return effectiveRequiredScopes.subtracting(effectiveGrantedScopes)
        }

        let missingFromDiagnostics = requiredWriteScopes.subtracting(knownGrantedScopes)
        return missingFromDiagnostics.isEmpty ? requiredWriteScopes : missingFromDiagnostics
    }

    private static func parsedScopeHeaders(from response: HTTPURLResponse) -> ParsedScopeHeaders {
        let headers = response.allHeaderFields
        let scope = headers.first { String(describing: $0.key).lowercased() == "scope" }?.value
        let oauthScope = headers.first { String(describing: $0.key).lowercased() == "x-oauth-scopes" }?.value
        let acceptedScope = headers.first { String(describing: $0.key).lowercased() == "x-accepted-oauth-scopes" }?.value

        return ParsedScopeHeaders(
            scopeHeader: parseScopeSet(from: scope),
            oauthScopeHeader: parseScopeSet(from: oauthScope),
            acceptedScopeHeader: parseScopeSet(from: acceptedScope)
        )
    }

    private static func parseScopeSet(from value: Any?) -> Set<String> {
        guard let value else { return [] }
        let scopeText = String(describing: value)
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        let rawScopes = scopeText.components(separatedBy: separators)
        return Set(rawScopes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    private static func scopesFromTokenDiagnostics(_ diagnostics: String) -> Set<String> {
        guard let scopeRange = diagnostics.range(of: "scopes=") else { return [] }
        let suffix = diagnostics[scopeRange.upperBound...]
        return parseScopeSet(from: String(suffix))
    }

    private static func spotifyAPIError(from data: Data) -> SpotifyAPIErrorDetail? {
        guard let payload = try? JSONDecoder().decode(SpotifyAPIErrorPayload.self, from: data) else {
            return nil
        }
        return payload.error
    }
}

struct PlaylistWriteProbeResult {
    let playlistID: String
    let ownershipOrCollaborativeAccess: Bool
    let missingWriteScopes: Set<String>
    let hasRequiredWriteScopes: Bool
    let details: String

    var canWrite: Bool {
        ownershipOrCollaborativeAccess && hasRequiredWriteScopes
    }
}

private struct PlaylistWriteContext {
    let signedInUserID: String
    let playlistID: String
    let ownerID: String
    let collaborative: Bool
    let ownershipMatches: Bool
    let isPublic: Bool

    var requiredWriteScopes: Set<String> {
        Set([isPublic ? "playlist-modify-public" : "playlist-modify-private"])
    }
}

private struct ParsedScopeHeaders {
    let scopeHeader: Set<String>
    let oauthScopeHeader: Set<String>
    let acceptedScopeHeader: Set<String>

    var hasAnyScopeHeaders: Bool {
        !scopeHeader.isEmpty || !oauthScopeHeader.isEmpty || !acceptedScopeHeader.isEmpty
    }
}

private struct SpotifyAPIErrorPayload: Decodable {
    let error: SpotifyAPIErrorDetail
}

private struct SpotifyAPIErrorDetail: Decodable {
    let status: Int?
    let message: String?
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
    let publicVisibility: Bool?
    let owner: Owner

    enum CodingKeys: String, CodingKey {
        case id
        case collaborative
        case publicVisibility = "public"
        case owner
    }

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
