import Foundation
import Combine
import SwiftUI
import CoreData

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
    private let persistence: Persistence

    init(persistence: Persistence = .shared, settings: AppSettings? = nil) {
        self.persistence = persistence
        if let settings {
            self.settings = settings
            persist(settings)
        } else if let persisted = Self.load(from: persistence) {
            self.settings = persisted
        } else {
            let initial = AppSettings()
            self.settings = initial
            persist(initial)
        }
    }

    func update(_ transform: (inout AppSettings) -> Void) {
        transform(&settings)
        persist(settings)
    }

    private func persist(_ settings: AppSettings) {
        let context = persistence.container.viewContext
        let request = NSFetchRequest<SettingsEntity>(entityName: "SettingsEntity")
        request.fetchLimit = 1
        let entity = (try? context.fetch(request))?.first ?? SettingsEntity(context: context)
        entity.id = settings.id
        entity.spotifyPlaylistID = settings.spotifyPlaylistID
        entity.market = settings.market
        entity.addEntireAlbum = settings.addEntireAlbum
        entity.featureThreshold = settings.featureThreshold
        persistence.save()
    }

    private static func load(from persistence: Persistence) -> AppSettings? {
        let context = persistence.container.viewContext
        let request = NSFetchRequest<SettingsEntity>(entityName: "SettingsEntity")
        request.fetchLimit = 1
        guard let entity = try? context.fetch(request).first else { return nil }
        guard let entity else { return nil }
        return AppSettings(
            id: entity.id,
            spotifyPlaylistID: entity.spotifyPlaylistID,
            market: entity.market ?? Locale.current.region?.identifier ?? "US",
            addEntireAlbum: entity.addEntireAlbum,
            featureThreshold: entity.featureThreshold
        )
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
