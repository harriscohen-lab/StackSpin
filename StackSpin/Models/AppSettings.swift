import Foundation
import Combine

struct AppSettings: Identifiable, Codable {
    let id: UUID
    var spotifyPlaylistID: String?
    var market: String
    var addEntireAlbum: Bool
    var featureThreshold: Double

    init(
        id: UUID = UUID(),
        spotifyPlaylistID: String? = nil,
        market: String = Locale.current.region?.identifier ?? "US",
        addEntireAlbum: Bool = true,
        featureThreshold: Double = 13.5
    ) {
        self.id = id
        self.spotifyPlaylistID = spotifyPlaylistID
        self.market = market
        self.addEntireAlbum = addEntireAlbum
        self.featureThreshold = featureThreshold
    }
}

final class AppSettingsStore: ObservableObject {
    @Published var settings: AppSettings

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    func update(_ transform: (inout AppSettings) -> Void) {
        transform(&settings)
        // TODO(MVP): Persist to Core Data
    }
}

private struct SettingsStoreKey: EnvironmentKey {
    static let defaultValue: AppSettingsStore = .init()
}

extension EnvironmentValues {
    var settingsStore: AppSettingsStore {
        get { self[SettingsStoreKey.self] }
        set { self[SettingsStoreKey.self] = newValue }
    }
}
