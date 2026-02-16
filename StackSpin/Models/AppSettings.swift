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

extension AppSettings {
    static func normalizedPlaylistID(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let range = trimmed.range(of: "spotify:playlist:", options: .caseInsensitive) {
            let value = String(trimmed[range.upperBound...])
            return value.split(separator: "?").first.map(String.init) ?? value
        }

        if let url = URL(string: trimmed),
           let host = url.host?.lowercased(),
           host.contains("spotify.com") {
            let pathParts = url.pathComponents.filter { $0 != "/" }
            if let playlistIndex = pathParts.firstIndex(where: { $0.lowercased() == "playlist" }),
               playlistIndex + 1 < pathParts.count {
                return pathParts[playlistIndex + 1]
            }
        }

        return trimmed
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
        entity.spotifyPlaylistID = AppSettings.normalizedPlaylistID(from: settings.spotifyPlaylistID)
        entity.market = settings.market
        entity.addEntireAlbum = settings.addEntireAlbum
        entity.featureThreshold = settings.featureThreshold
        persistence.save()
    }

    private static func load(from persistence: Persistence) -> AppSettings? {
        let context = persistence.container.viewContext
        let request = NSFetchRequest<SettingsEntity>(entityName: "SettingsEntity")
        request.fetchLimit = 1
        guard let results = try? context.fetch(request),
              let entity = results.first else { return nil }
        return AppSettings(
            id: entity.id,
            spotifyPlaylistID: AppSettings.normalizedPlaylistID(from: entity.spotifyPlaylistID),
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
