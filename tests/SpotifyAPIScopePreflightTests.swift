import Foundation
import XCTest
@testable import StackSpin

final class SpotifyAPIScopePreflightTests: XCTestCase {
    override func setUp() {
        super.setUp()
        SpotifyAPIScopePreflightURLProtocol.requestLog = []
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
}

private final class SpotifyAPIScopePreflightURLProtocol: URLProtocol {
    static var requestLog: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requestLog.append(request)
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
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
