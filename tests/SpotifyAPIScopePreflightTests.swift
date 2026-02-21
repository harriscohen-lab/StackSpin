import Foundation
import XCTest
@testable import StackSpin

final class SpotifyAPIScopePreflightTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SpotifyAPIScopePreflightURLProtocol.requestLog = []
        SpotifyAPIScopePreflightURLProtocol.requestHandler = nil
        URLProtocol.registerClass(SpotifyAPIScopePreflightURLProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(SpotifyAPIScopePreflightURLProtocol.self)
        super.tearDown()
    }

    func testOwnershipMatchButMissingPublicWriteScopeBlocksBeforeAddTracksPost() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpotifyAPIScopePreflightURLProtocol.self]
        let session = URLSession(configuration: config)

        let auth = SpotifyAuthController()
        auth.debugInjectTokens(
            SpotifyTokens(
                accessToken: "access",
                refreshToken: "refresh",
                expirationDate: Date().addingTimeInterval(3600),
                generation: 0,
                grantedScopes: ["playlist-modify-private", "playlist-read-private"]
            )
        )

        var callbackMissingScopes: Set<String> = []
        let api = SpotifyAPI(
            authController: auth,
            session: session,
            onMissingWriteScopes: { callbackMissingScopes = $0 }
        )

        do {
            try await api.addTracks(playlistID: "playlist123", trackURIs: ["spotify:track:1"])
            XCTFail("Expected local preflight scope failure")
        } catch let appError as AppError {
            guard case .network(let message) = appError else {
                XCTFail("Unexpected app error: \(appError)")
                return
            }
            XCTAssertTrue(message.contains("playlist-modify-public"))
            XCTAssertTrue(message.contains("force Spotify's consent dialog"))
        }

        XCTAssertEqual(callbackMissingScopes, ["playlist-modify-public"])
        XCTAssertTrue(
            SpotifyAPIScopePreflightURLProtocol.requestLog.contains { $0.httpMethod == "GET" && $0.url?.path == "/v1/me" }
        )
        XCTAssertTrue(
            SpotifyAPIScopePreflightURLProtocol.requestLog.contains { $0.httpMethod == "GET" && $0.url?.path.contains("/v1/playlists/playlist123") == true }
        )
        XCTAssertFalse(
            SpotifyAPIScopePreflightURLProtocol.requestLog.contains { $0.httpMethod == "POST" && $0.url?.path == "/v1/playlists/playlist123/tracks" }
        )
    }


    func testProbeOwnershipMatchButMissingPublicWriteScopeReturnsActionableFailure() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpotifyAPIScopePreflightURLProtocol.self]
        let session = URLSession(configuration: config)

        let auth = SpotifyAuthController()
        auth.debugInjectTokens(
            SpotifyTokens(
                accessToken: "access",
                refreshToken: "refresh",
                expirationDate: Date().addingTimeInterval(3600),
                generation: 0,
                grantedScopes: ["playlist-modify-private", "playlist-read-private"]
            )
        )

        let api = SpotifyAPI(authController: auth, session: session)
        let probe = try await api.probePlaylistWriteAccess(playlistID: "playlist123")

        XCTAssertTrue(probe.ownershipOrCollaborativeAccess)
        XCTAssertFalse(probe.hasRequiredWriteScopes)
        XCTAssertEqual(probe.missingWriteScopes, ["playlist-modify-public"])
        XCTAssertFalse(probe.canWrite)
        XCTAssertTrue(probe.details.contains("Missing required Spotify scope(s): playlist-modify-public"))
        XCTAssertTrue(probe.details.contains("Reconnect Spotify and approve these permissions"))
    }

    func testProbeOwnershipMatchAndPublicWriteScopePresentPasses() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpotifyAPIScopePreflightURLProtocol.self]
        let session = URLSession(configuration: config)

        let auth = SpotifyAuthController()
        auth.debugInjectTokens(
            SpotifyTokens(
                accessToken: "access",
                refreshToken: "refresh",
                expirationDate: Date().addingTimeInterval(3600),
                generation: 0,
                grantedScopes: ["playlist-modify-public", "playlist-read-private"]
            )
        )

        let api = SpotifyAPI(authController: auth, session: session)
        let probe = try await api.probePlaylistWriteAccess(playlistID: "playlist123")

        XCTAssertTrue(probe.ownershipOrCollaborativeAccess)
        XCTAssertTrue(probe.hasRequiredWriteScopes)
        XCTAssertEqual(probe.missingWriteScopes, [])
        XCTAssertTrue(probe.canWrite)
    }

    func testUnknownGrantedScopesDoesNotBlockPreflight() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpotifyAPIScopePreflightURLProtocol.self]
        let session = URLSession(configuration: config)

        let auth = SpotifyAuthController()
        auth.debugInjectTokens(
            SpotifyTokens(
                accessToken: "access",
                refreshToken: "refresh",
                expirationDate: Date().addingTimeInterval(3600),
                generation: 0,
                grantedScopes: []
            )
        )

        var callbackMissingScopes: Set<String> = []
        let api = SpotifyAPI(
            authController: auth,
            session: session,
            onMissingWriteScopes: { callbackMissingScopes = $0 }
        )

        try await api.addTracks(playlistID: "playlist123", trackURIs: ["spotify:track:1"])

        XCTAssertEqual(callbackMissingScopes, [])
        XCTAssertTrue(
            SpotifyAPIScopePreflightURLProtocol.requestLog.contains { $0.httpMethod == "POST" && $0.url?.path == "/v1/playlists/playlist123/tracks" }
        )
    }

    func testForbiddenPostMarksReconsentForMissingWriteScopes() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SpotifyAPIScopePreflightURLProtocol.self]
        let session = URLSession(configuration: config)

        let auth = SpotifyAuthController()
        auth.debugInjectTokens(
            SpotifyTokens(
                accessToken: "access",
                refreshToken: "refresh",
                expirationDate: Date().addingTimeInterval(3600),
                generation: 0,
                grantedScopes: ["playlist-modify-public", "playlist-read-private"]
            )
        )

        var callbackMissingScopes: Set<String> = []
        SpotifyAPIScopePreflightURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            switch (request.httpMethod ?? "GET", url.host ?? "", url.path) {
            case ("GET", "api.spotify.com", "/v1/me"):
                return (
                    200,
                    nil,
                    Data(#"{"id":"owner123"}"#.utf8)
                )
            case ("GET", "api.spotify.com", "/v1/playlists/playlist123"):
                return (
                    200,
                    nil,
                    Data(#"{"id":"playlist123","collaborative":false,"public":true,"owner":{"id":"owner123"}}"#.utf8)
                )
            case ("POST", "api.spotify.com", "/v1/playlists/playlist123/tracks"):
                return (
                    403,
                    [
                        "x-oauth-scopes": "playlist-read-private",
                        "x-accepted-oauth-scopes": "playlist-modify-public playlist-modify-private"
                    ],
                    Data(#"{"error":{"status":403,"message":"Insufficient client scope"}}"#.utf8)
                )
            case ("POST", "accounts.spotify.com", "/api/token"):
                return (
                    400,
                    nil,
                    Data(#"{"error":"invalid_grant"}"#.utf8)
                )
            default:
                return (200, nil, Data(#"{"snapshot_id":"ignored"}"#.utf8))
            }
        }

        let api = SpotifyAPI(
            authController: auth,
            session: session,
            onMissingWriteScopes: { callbackMissingScopes = $0 }
        )

        do {
            try await api.addTracks(playlistID: "playlist123", trackURIs: ["spotify:track:1"])
            XCTFail("Expected permissions error after forbidden add-tracks POST")
        } catch let appError as AppError {
            guard case .spotifyPermissionsExpiredOrInsufficient = appError else {
                XCTFail("Unexpected app error: \(appError)")
                return
            }
        }

        XCTAssertEqual(callbackMissingScopes, ["playlist-modify-public"])
        XCTAssertEqual(auth.debugPendingScopeReconsentScopes(), ["playlist-modify-public"])
    }
}

private final class SpotifyAPIScopePreflightURLProtocol: URLProtocol {
    static var requestLog: [URLRequest] = []
    static var requestHandler: ((URLRequest) throws -> (statusCode: Int, headers: [String: String]?, body: Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestLog.append(request)
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        if let requestHandler = Self.requestHandler {
            do {
                let output = try requestHandler(request)
                let response = HTTPURLResponse(url: url, statusCode: output.statusCode, httpVersion: nil, headerFields: output.headers)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: output.body)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
            return
        }

        let body: String
        switch (request.httpMethod ?? "GET", url.path) {
        case ("GET", "/v1/me"):
            body = #"{"id":"owner123"}"#
        case ("GET", "/v1/playlists/playlist123"):
            body = #"{"id":"playlist123","collaborative":false,"public":true,"owner":{"id":"owner123"}}"#
        default:
            body = #"{"snapshot_id":"ignored"}"#
        }

        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
