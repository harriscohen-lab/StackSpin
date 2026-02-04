import Foundation

enum JobState: String, Codable, CaseIterable, Identifiable {
    case pending
    case matching
    case needsConfirm
    case adding
    case complete
    case failed

    var id: String { rawValue }
}

struct Job: Identifiable, Codable {
    let id: UUID
    var createdAt: Date
    var state: JobState
    var photoLocalID: String
    var barcode: String?
    var ocrText: [String]
    var candidateMBIDs: [AlbumMatch]
    var chosenMBID: String?
    var chosenSpotifyAlbumID: String?
    var addedTrackIDs: [String]
    var errorDescription: String?

    init(
        id: UUID = UUID(),
        createdAt: Date = .init(),
        state: JobState = .pending,
        photoLocalID: String,
        barcode: String? = nil,
        ocrText: [String] = [],
        candidateMBIDs: [AlbumMatch] = [],
        chosenMBID: String? = nil,
        chosenSpotifyAlbumID: String? = nil,
        addedTrackIDs: [String] = [],
        errorDescription: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.state = state
        self.photoLocalID = photoLocalID
        self.barcode = barcode
        self.ocrText = ocrText
        self.candidateMBIDs = candidateMBIDs
        self.chosenMBID = chosenMBID
        self.chosenSpotifyAlbumID = chosenSpotifyAlbumID
        self.addedTrackIDs = addedTrackIDs
        self.errorDescription = errorDescription
    }
}
