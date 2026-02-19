import CoreData
import Foundation
import UIKit
import Photos

final class Resolver {
    private let musicBrainz: MusicBrainzAPI
    private let discogs: DiscogsAPI
    private let spotify: SpotifyAPI
    private let ocr: OCRService
    private let featureMatcher: FeaturePrintMatcher
    private let persistence: Persistence

    init(
        musicBrainz: MusicBrainzAPI,
        discogs: DiscogsAPI,
        spotify: SpotifyAPI,
        ocr: OCRService,
        featureMatcher: FeaturePrintMatcher,
        persistence: Persistence = .shared
    ) {
        self.musicBrainz = musicBrainz
        self.discogs = discogs
        self.spotify = spotify
        self.ocr = ocr
        self.featureMatcher = featureMatcher
        self.persistence = persistence
    }

    func resolve(job: inout Job, settings: AppSettings) async throws {
        if let barcode = job.barcode, !barcode.isEmpty {
            if try await resolveViaBarcode(&job, barcode: barcode, market: settings.market) {
                return
            }
        }
        if job.ocrText.isEmpty {
            if let image = loadImage(job.photoLocalID), let cgImage = image.cgImage {
                do {
                    let text = try await ocr.extractText(from: cgImage)
                    job.ocrText = text
                } catch {
                    NSLog("OCR extraction failed, continuing without OCR text: \(error)")
                }
            }
        }
        let parsed = OCRHeuristics.parseCandidate(from: job.ocrText)
        if try await resolveViaText(&job, parsed: parsed, settings: settings) {
            return
        }
        if let image = loadImage(job.photoLocalID), let cgImage = image.cgImage {
            do {
                if let best = try await featureMatcher.nearestNeighborDistance(query: cgImage),
                   best.distance < Float(settings.featureThreshold) {
                    job.chosenMBID = best.mbid
                    job.state = .needsConfirm
                    return
                }
            } catch {
                NSLog("Feature print matching failed, continuing without cache match: \(error)")
            }
        }

        throw AppError.network("No confident match")
    }

    private func resolveViaBarcode(_ job: inout Job, barcode: String, market: String) async throws -> Bool {
        for candidate in barcodeCandidates(from: barcode) {
            let releases = try await musicBrainz.releaseByBarcode(candidate)
            if !releases.isEmpty {
                let match = releases.first!
                try await enrichJob(&job, with: match, market: market)
                return true
            }
            let discogsReleases: [DiscogsRelease]
            do {
                discogsReleases = try await discogs.searchByBarcode(candidate)
            } catch {
                NSLog("Discogs barcode lookup failed for candidate \(candidate): \(error)")
                continue
            }

            if let first = discogsReleases.first {
                let release = MBRelease(
                    id: String(first.id),
                    title: first.title,
                    artistCredit: first.artist,
                    date: first.year.map { String($0) },
                    label: first.label,
                    barcode: first.barcode,
                    country: nil
                )
                do {
                    try await enrichJob(&job, with: release, market: market)
                    return true
                } catch {
                    NSLog("Discogs release enrichment failed for candidate \(candidate): \(error)")
                    throw error
                }
            }
        }
        return false
    }

    private func barcodeCandidates(from barcode: String) -> [String] {
        let digitsOnly = barcode.filter(\.isNumber)
        guard !digitsOnly.isEmpty else {
            return [barcode]
        }

        var candidates: [String] = [digitsOnly]
        if digitsOnly.count == 12 {
            candidates.append("0\(digitsOnly)")
        } else if digitsOnly.count == 13, digitsOnly.first == "0" {
            candidates.append(String(digitsOnly.dropFirst()))
        }
        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    private func resolveViaText(_ job: inout Job, parsed: (artist: String?, album: String?, catno: String?), settings: AppSettings) async throws -> Bool {
        let releases = try await musicBrainz.searchRelease(artist: parsed.artist, album: parsed.album, catno: parsed.catno)
        guard !releases.isEmpty else { return false }
        let candidates = releases.prefix(3).map { release -> AlbumMatch in
            AlbumMatch(
                mbid: release.id,
                title: release.title,
                artist: release.artistCredit,
                year: release.date,
                label: release.label,
                score: 0.5,
                artworkURL: musicBrainz.coverThumbURL(for: release.id)
            )
        }
        if candidates.count == 1 {
            try await enrichJob(&job, with: releases[0], market: settings.market)
            return true
        } else {
            job.candidateMBIDs = candidates
            job.state = .needsConfirm
            return true
        }
    }

    private func enrichJob(_ job: inout Job, with release: MBRelease, market: String) async throws {
        let album = try await spotify.searchAlbum(artist: release.artistCredit, title: release.title, market: market)
        guard let album else {
            throw AppError.network("Spotify album not found")
        }
        job.chosenMBID = release.id
        job.chosenSpotifyAlbumID = album.id
        job.state = .matching
        if let image = loadImage(job.photoLocalID), let cgImage = image.cgImage {
            await featureMatcher.storeFeaturePrint(cgImage, mbid: release.id)
        }
    }

    private func loadImage(_ identifier: String) -> UIImage? {
        if let cached = ImageCache.shared.image(forKey: identifier) {
            return cached
        }
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = true
        var resultImage: UIImage?
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = assets.firstObject else { return nil }
        manager.requestImage(for: asset, targetSize: CGSize(width: 600, height: 600), contentMode: .aspectFit, options: options) { image, _ in
            resultImage = image
        }
        if let resultImage {
            ImageCache.shared.store(image: resultImage, forKey: identifier)
        }
        return resultImage
    }
}
