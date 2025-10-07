import CoreData

@objc(AlbumCacheItemEntity)
final class AlbumCacheItemEntity: NSManagedObject {
    @NSManaged var mbid: String?
    @NSManaged var title: String?
    @NSManaged var artist: String?
    @NSManaged var year: String?
    @NSManaged var label: String?
    @NSManaged var market: String?
    @NSManaged var coverThumbLocalPath: String?
    @NSManaged var featurePrintData: Data?
    @NSManaged var lastUsedAt: Date?
}

@objc(JobEntity)
final class JobEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var createdAt: Date
    @NSManaged var state: String
    @NSManaged var photoLocalID: String
    @NSManaged var barcode: String?
    @NSManaged var ocrText: Data?
    @NSManaged var candidateMBIDs: Data?
    @NSManaged var chosenMBID: String?
    @NSManaged var chosenSpotifyAlbumID: String?
    @NSManaged var addedTrackIDs: Data?
    @NSManaged var errorDescription: String?
}

@objc(SettingsEntity)
final class SettingsEntity: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var spotifyPlaylistID: String?
    @NSManaged var market: String?
    @NSManaged var addEntireAlbum: Bool
    @NSManaged var featureThreshold: Double
}

@objc(DedupeEntity)
final class DedupeEntity: NSManagedObject {
    @NSManaged var playlistID: String
    @NSManaged var trackID: String
}
