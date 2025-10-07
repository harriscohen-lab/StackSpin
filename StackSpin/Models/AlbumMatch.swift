import Foundation
import SwiftUI

struct AlbumMatch: Identifiable, Codable, Hashable {
    let id: UUID
    let mbid: String
    let title: String
    let artist: String
    let year: String?
    let label: String?
    let score: Double
    let artworkURL: URL?

    init(
        id: UUID = UUID(),
        mbid: String,
        title: String,
        artist: String,
        year: String? = nil,
        label: String? = nil,
        score: Double,
        artworkURL: URL? = nil
    ) {
        self.id = id
        self.mbid = mbid
        self.title = title
        self.artist = artist
        self.year = year
        self.label = label
        self.score = score
        self.artworkURL = artworkURL
    }
}

struct SpotifyAlbum: Identifiable, Codable {
    let id: String
    let name: String
    let artist: String
    let imageURL: URL?
    let uri: String
}

struct SpotifyTrack: Identifiable, Codable {
    let id: String
    let name: String
    let uri: String
    let discNumber: Int
    let trackNumber: Int
}

struct MBRelease: Identifiable, Codable {
    let id: String
    let title: String
    let artistCredit: String
    let date: String?
    let label: String?
    let barcode: String?
    let country: String?
}

struct DGRelease: Identifiable, Codable {
    let id: Int
    let title: String
    let artist: String
    let year: Int?
    let label: String?
    let barcode: String?
}
