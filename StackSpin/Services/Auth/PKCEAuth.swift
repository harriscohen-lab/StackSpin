import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import os
import UIKit
import Security

struct SpotifyTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expirationDate: Date
    let generation: Int
    let grantedScopes: [String]

    init(accessToken: String, refreshToken: String, expirationDate: Date, generation: Int = 0, grantedScopes: [String] = []) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expirationDate = expirationDate
        self.generation = generation
        self.grantedScopes = grantedScopes
    }

    enum CodingKeys: String, CodingKey {
        case accessToken
        case refreshToken
        case expirationDate
        case generation
        case grantedScopes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        expirationDate = try container.decode(Date.self, forKey: .expirationDate)
        generation = try container.decodeIfPresent(Int.self, forKey: .generation) ?? 0
        grantedScopes = try container.decodeIfPresent([String].self, forKey: .grantedScopes) ?? []
    }
}

final class SpotifyAuthController: NSObject, ObservableObject {
    @Published private(set) var tokens: SpotifyTokens?
    @Published private(set) var tokenSource: String = "none"
    private var currentSession: ASWebAuthenticationSession?
    private let clientID: String
    private let redirectURI = URL(string: "stackspin://auth")!
    private let keychain = KeychainHelper()
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "StackSpin",
        category: "SpotifyAuth"
    )
    private let transientRetryDelayNanoseconds: UInt64 = 400_000_000
    private let defaultSpotifyScopes = [
        "playlist-modify-public",
        "playlist-modify-private",
        "playlist-read-private",
        "playlist-read-collaborative"
    ]
    private var pendingScopeReconsent: Set<String> = []
    private(set) var hasPromptedScopeReconsentThisSession = false

    var tokenDiagnostics: String {
        let generation = tokens?.generation ?? -1
        let scopes = tokens?.grantedScopes.sorted().joined(separator: ",") ?? "<none>"
        return "source=\(tokenSource) generation=\(generation) scopes=\(scopes)"
    }

    var grantedScopes: Set<String> {
        Set(tokens?.grantedScopes ?? [])
    }

    override init() {
        self.clientID = Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String ?? ""
        super.init()
    }

    func isAuthorized() -> Bool {
        guard let tokens else { return false }
        return tokens.expirationDate > Date()
    }

    @MainActor
    func signIn() async throws {
        guard !clientID.isEmpty else { throw AppError.spotifyAuth }

        let verifier = CodeVerifier()
        let challenge = verifier.challenge
        let state = UUID().uuidString

        let forcedScopeSet = Set(defaultSpotifyScopes).union(pendingScopeReconsent)
        let shouldShowDialog = !pendingScopeReconsent.isEmpty
        if shouldShowDialog {
            hasPromptedScopeReconsentThisSession = true
        }

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: forcedScopeSet.sorted().joined(separator: " ")),
            URLQueryItem(name: "show_dialog", value: shouldShowDialog ? "true" : "false"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components.url else { throw AppError.spotifyAuth }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: redirectURI.scheme) { [weak self] callbackURL, error in
                Task { @MainActor in
                    defer { self?.currentSession = nil }

                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        continuation.resume(throwing: AppError.spotifyAuthCancelled)
                        return
                    }

                    if error != nil {
                        continuation.resume(throwing: AppError.spotifyAuth)
                        return
                    }

                    guard let self else {
                        continuation.resume(throwing: AppError.unknown)
                        return
                    }

                    guard let callbackURL else {
                        continuation.resume(throwing: AppError.spotifyAuth)
                        return
                    }

                    do {
                        try await self.handleCallback(url: callbackURL, verifier: verifier, expectedState: state)
                        continuation.resume(returning: ())
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            self.currentSession = session
            session.presentationContextProvider = self
            guard session.start() else {
                self.currentSession = nil
                continuation.resume(throwing: AppError.spotifyAuth)
                return
            }
        }
    }

    func restoreIfPossible() async {
        if let stored: SpotifyTokens = keychain.read(key: "spotifyTokens") {
            await MainActor.run {
                self.tokens = stored
                self.tokenSource = "restored"
            }
        }
    }

    func withValidToken() async throws -> String {
        if let tokens, tokens.expirationDate > Date().addingTimeInterval(30) {
            return tokens.accessToken
        }
        return try await refreshToken()
    }

    func forceRefreshToken() async throws -> String {
        try await refreshToken()
    }

    private func refreshToken() async throws -> String {
        guard let tokens else { throw AppError.spotifyAuth }
        let body = [
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": clientID
        ].percentEncoded()
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let payload = try await performTokenRequest(request, operation: "refresh")
        let grantedScopes = Self.mergeGrantedScopes(payloadScope: payload.scope, fallbackScopes: tokens.grantedScopes)
        let rotatedRefreshToken = payload.refreshToken?.isEmpty == false
        let finalRefreshToken = rotatedRefreshToken ? payload.refreshToken! : tokens.refreshToken
        logger.debug(
            "Spotify token refresh succeeded generationBefore=\(tokens.generation, privacy: .public) refreshTokenRotatedAndPersisted=\(rotatedRefreshToken, privacy: .public) grantedScopes=\(grantedScopes.sorted().joined(separator: ","), privacy: .public)"
        )
        let newTokens = SpotifyTokens(
            accessToken: payload.accessToken,
            refreshToken: finalRefreshToken,
            expirationDate: Date().addingTimeInterval(TimeInterval(payload.expiresIn)),
            generation: tokens.generation + 1,
            grantedScopes: grantedScopes.sorted()
        )
        keychain.write(newTokens, key: "spotifyTokens")
        await MainActor.run {
            self.tokens = newTokens
            self.tokenSource = "refreshed"
        }
        return newTokens.accessToken
    }

    private func handleCallback(url: URL, verifier: CodeVerifier, expectedState: String) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AppError.spotifyAuth
        }

        let queryItems = components.queryItems ?? []

        if let callbackError = queryItems.first(where: { $0.name == "error" })?.value {
            if callbackError == "access_denied" {
                throw AppError.spotifyAuthCancelled
            }

            let message = queryItems.first(where: { $0.name == "error_description" })?.value ?? callbackError
            throw AppError.network("Spotify authorization failed: \(message)")
        }

        if let callbackState = queryItems.first(where: { $0.name == "state" })?.value,
           callbackState != expectedState {
            throw AppError.spotifyAuthStateMismatch
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw AppError.spotifyAuth
        }

        let body = [
            "client_id": clientID,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI.absoluteString,
            "code_verifier": verifier.verifier
        ].percentEncoded()

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let payload = try await performTokenRequest(request, operation: "exchange")
        let grantedScopes = Self.mergeGrantedScopes(
            payloadScope: payload.scope,
            fallbackScopes: self.tokens?.grantedScopes ?? defaultSpotifyScopes
        )
        logger.debug(
            "Spotify token exchange succeeded refreshTokenReturned=\(payload.refreshToken != nil, privacy: .public) previousTokenExists=\(self.tokens != nil, privacy: .public) grantedScopes=\(grantedScopes.sorted().joined(separator: ","), privacy: .public)"
        )
        if payload.refreshToken == nil, self.tokens?.refreshToken != nil {
            logger.error(
                "Spotify token exchange missing refresh token; falling back to existing stored refresh token generation=\(self.tokens?.generation ?? -1, privacy: .public)"
            )
        }
        let tokens = SpotifyTokens(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken ?? self.tokens?.refreshToken ?? "",
            expirationDate: Date().addingTimeInterval(TimeInterval(payload.expiresIn)),
            generation: (self.tokens?.generation ?? -1) + 1,
            grantedScopes: grantedScopes.sorted()
        )
        keychain.write(tokens, key: "spotifyTokens")
        await MainActor.run {
            self.tokens = tokens
            self.tokenSource = "exchange"
            self.pendingScopeReconsent.subtract(tokens.grantedScopes)
        }
    }

    func markScopeReconsentRequired(missingScopes: Set<String>) {
        guard !missingScopes.isEmpty else { return }
        pendingScopeReconsent.formUnion(missingScopes)
    }

    private static func mergeGrantedScopes(payloadScope: String?, fallbackScopes: [String]) -> Set<String> {
        let parsedScopes = Set((payloadScope ?? "").split(separator: " ").map(String.init))
        return parsedScopes.isEmpty ? Set(fallbackScopes) : parsedScopes
    }

    private func performTokenRequest(_ request: URLRequest, operation: String) async throws -> TokenResponse {
        var attempt = 0
        while true {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    let bodySnippet = Self.responseSnippet(from: data)
                    logger.error(
                        "Spotify token \(operation, privacy: .public) failed. status=\(statusCode, privacy: .public) body=\(bodySnippet, privacy: .public)"
                    )

                    if let authError = try? JSONDecoder().decode(TokenErrorResponse.self, from: data),
                       authError.isDefinitiveAuthFailure {
                        logger.error("Spotify token \(operation, privacy: .public) definitive auth failure; clearing cached credentials")
                        await clearCachedTokens()
                        throw AppError.spotifyAuth
                    }

                    throw AppError.network("Spotify \(operation) failed")
                }

                return try JSONDecoder().decode(TokenResponse.self, from: data)
            } catch let urlError as URLError {
                guard shouldRetryAfterTransportFailure(urlError, attempt: attempt, operation: operation) else {
                    throw AppError.network("Spotify \(operation) failed")
                }

                attempt += 1
                try await Task.sleep(nanoseconds: transientRetryDelayNanoseconds)
            }
        }
    }

    private func shouldRetryAfterTransportFailure(_ error: URLError, attempt: Int, operation: String) -> Bool {
        let canRetry = attempt == 0
        switch error.code {
        case .notConnectedToInternet:
            logger.error(
                "Spotify token \(operation, privacy: .public) transport failure: no internet connection. retrying=\(canRetry, privacy: .public)"
            )
            return canRetry
        case .timedOut:
            logger.error(
                "Spotify token \(operation, privacy: .public) transport failure: request timed out. retrying=\(canRetry, privacy: .public)"
            )
            return canRetry
        case .cannotFindHost:
            logger.error(
                "Spotify token \(operation, privacy: .public) transport failure: cannot find host. retrying=\(canRetry, privacy: .public)"
            )
            return canRetry
        case .networkConnectionLost:
            logger.error(
                "Spotify token \(operation, privacy: .public) transport failure: network connection lost. retrying=\(canRetry, privacy: .public)"
            )
            return canRetry
        default:
            logger.error(
                "Spotify token \(operation, privacy: .public) transport error: \(error.localizedDescription, privacy: .public)"
            )
            return false
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
}


#if DEBUG
extension SpotifyAuthController {
    func debugInjectTokens(_ tokens: SpotifyTokens) {
        self.tokens = tokens
        self.tokenSource = "debug"
    }

    func debugResetPromptState() {
        self.pendingScopeReconsent = []
        self.hasPromptedScopeReconsentThisSession = false
    }

    func debugPendingScopeReconsentScopes() -> Set<String> {
        pendingScopeReconsent
    }
}
#endif

private extension SpotifyAuthController {
    func clearCachedTokens() async {
        keychain.delete(key: "spotifyTokens")
        await MainActor.run {
            self.tokens = nil
            self.tokenSource = "cleared"
        }
    }
}

extension SpotifyAuthController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }
}

private struct TokenErrorResponse: Decodable {
    let error: String

    var isDefinitiveAuthFailure: Bool {
        error == "invalid_grant" || error == "invalid_client"
    }
}

private struct CodeVerifier {
    let verifier: String
    let challenge: String

    init() {
        let data = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        verifier = data.base64URLEncodedString()
        challenge = Self.codeChallenge(for: verifier)
    }

    private static func codeChallenge(for verifier: String) -> String {
        let hashed = SHA256.hash(data: Data(verifier.utf8))
        return Data(hashed).base64URLEncodedString()
    }
}

private final class KeychainHelper {
    func write<T: Codable>(_ value: T, key: String) {
        do {
            let data = try JSONEncoder().encode(value)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrAccount as String: key,
                kSecValueData as String: data
            ]
            SecItemDelete(query as CFDictionary)
            let status = SecItemAdd(query as CFDictionary, nil)
            if status != errSecSuccess {
                NSLog("Keychain write failed: \(status)")
            }
        } catch {
            NSLog("Keychain encode failed: \(error)")
        }
    }

    func read<T: Codable>(key: String) -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private extension Dictionary where Key == String, Value == String {
    func percentEncoded() -> Data? {
        map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
        }
        .joined(separator: "&")
        .data(using: .utf8)
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
