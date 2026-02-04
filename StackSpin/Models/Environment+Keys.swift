import SwiftUI

private struct SpotifyAuthKey: EnvironmentKey {
    static let defaultValue: SpotifyAuthController = .init()
}

extension EnvironmentValues {
    var spotifyAuth: SpotifyAuthController {
        get { self[SpotifyAuthKey.self] }
        set { self[SpotifyAuthKey.self] = newValue }
    }
}
