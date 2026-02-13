import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import UIKit
import Security

struct SpotifyTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expirationDate: Date
}

final class SpotifyAuthController: NSObject, ObservableObject {
    @Published private(set) var tokens: SpotifyTokens?
    private var currentSession: ASWebAuthenticationSession?
    private let clientID = "YOUR_SPOTIFY_CLIENT_ID" // TODO: Move to config
    private let redirectURI = URL(string: "stackspin://auth")!
    private let keychain = KeychainHelper()

    func isAuthorized() -> Bool {
        guard let tokens else { return false }
        return tokens.expirationDate > Date()
    }

    @MainActor
    func signIn() async throws {
        let verifier = CodeVerifier()
        let challenge = verifier.challenge
        let state = UUID().uuidString

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI.absoluteString),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: "playlist-modify-public playlist-modify-private"),
            URLQueryItem(name: "state", value: state)
        ]

        guard let url = components.url else { throw AppError.spotifyAuth }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: redirectURI.scheme) { [weak self] callbackURL, error in
            guard let callbackURL, error == nil else {
                return
            }
            Task {
                await self?.handleCallback(url: callbackURL, verifier: verifier)
            }
        }
        currentSession = session
        session.presentationContextProvider = self
        session.start()
    }

    func restoreIfPossible() async {
        if let stored: SpotifyTokens = keychain.read(key: "spotifyTokens") {
            await MainActor.run {
                self.tokens = stored
            }
        }
    }

    func withValidToken() async throws -> String {
        if let tokens, tokens.expirationDate > Date().addingTimeInterval(30) {
            return tokens.accessToken
        }
        return try await refreshToken()
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AppError.network("Spotify refresh failed")
        }
        let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
        let newTokens = SpotifyTokens(
            accessToken: payload.accessToken,
            refreshToken: tokens.refreshToken,
            expirationDate: Date().addingTimeInterval(TimeInterval(payload.expiresIn))
        )
        keychain.write(newTokens, key: "spotifyTokens")
        await MainActor.run {
            self.tokens = newTokens
        }
        return newTokens.accessToken
    }

    private func handleCallback(url: URL, verifier: CodeVerifier) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else { return }

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

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw AppError.network("Spotify sign-in failed")
            }
            let payload = try JSONDecoder().decode(TokenResponse.self, from: data)
            let tokens = SpotifyTokens(
                accessToken: payload.accessToken,
                refreshToken: payload.refreshToken ?? self.tokens?.refreshToken ?? "",
                expirationDate: Date().addingTimeInterval(TimeInterval(payload.expiresIn))
            )
            keychain.write(tokens, key: "spotifyTokens")
            await MainActor.run {
                self.tokens = tokens
            }
        } catch {
            NSLog("Auth callback error: \(error)")
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

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
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
