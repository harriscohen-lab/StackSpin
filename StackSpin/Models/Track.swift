import Foundation

struct Track: Identifiable, Codable, Hashable {
    let id: UUID
    let spotifyID: String
    let name: String
    let duration: TimeInterval
    let discNumber: Int
    let trackNumber: Int

    init(
        id: UUID = UUID(),
        spotifyID: String,
        name: String,
        duration: TimeInterval,
        discNumber: Int,
        trackNumber: Int
    ) {
        self.id = id
        self.spotifyID = spotifyID
        self.name = name
        self.duration = duration
        self.discNumber = discNumber
        self.trackNumber = trackNumber
    }
}
