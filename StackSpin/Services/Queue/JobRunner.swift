import BackgroundTasks
import Combine
import CoreData
import Foundation
import UIKit

@MainActor
final class JobRunner: ObservableObject {
    @Published private(set) var jobs: [Job] = []
    private let scheduler: BackgroundScheduler
    private let resolver: Resolver
    private let spotifyAPI: SpotifyAPI
    private let persistence: Persistence
    private var dedupeSet: Set<String> = []

    init(authController: SpotifyAuthController, persistence: Persistence) {
        self.spotifyAPI = SpotifyAPI(authController: authController)
        self.scheduler = BackgroundScheduler()
        self.persistence = persistence
        self.resolver = Resolver(
            musicBrainz: MusicBrainzAPI(),
            discogs: DiscogsAPI(),
            spotify: spotifyAPI,
            ocr: OCRService(),
            featureMatcher: FeaturePrintMatcher(persistence: persistence),
            persistence: persistence
        )
        self.dedupeSet = Self.loadDedupeSet(from: persistence)
        self.scheduler.onProcessRequested = { [weak self] in
            guard let self else { return false }
            await self.resumePendingJobs()
            return true
        }
    }

    func enqueue(job: Job, image: UIImage? = nil) {
        jobs.append(job)
        if let image {
            ImageCache.shared.store(image: image, forKey: job.photoLocalID)
        }
        persist(job)
        Task { await scheduler.scheduleIfNeeded() }
    }

    func processAll(settings: AppSettings) async {
        for index in jobs.indices {
            await processJob(at: index, settings: settings)
        }
    }

    func resumePendingJobs() async {
        jobs = Self.loadJobs(from: persistence)
    }

    private func processJob(at index: Int, settings: AppSettings) async {
        guard jobs.indices.contains(index) else { return }
        var job = jobs[index]
        do {
            job.state = .matching
            try await resolver.resolve(job: &job, settings: settings)
            if let playlist = AppSettings.normalizedPlaylistID(from: settings.spotifyPlaylistID),
               let albumID = job.chosenSpotifyAlbumID {
                let tracks = try await spotifyAPI.albumTracks(albumID: albumID)
                let newURIs = tracks.map { $0.uri }.filter { dedupeSet.insert($0).inserted }
                try await spotifyAPI.addTracks(playlistID: playlist, trackURIs: newURIs)
                persistDedupeEntries(playlistID: playlist, trackIDs: newURIs)
                job.addedTrackIDs = newURIs
                job.state = .complete
            } else {
                job.state = .needsConfirm
            }
        } catch {
            job.errorDescription = error.localizedDescription
            job.state = .failed
        }
        jobs[index] = job
        persist(job)
    }

    private func persist(_ job: Job) {
        let context = persistence.container.viewContext
        let request = NSFetchRequest<JobEntity>(entityName: "JobEntity")
        request.predicate = NSPredicate(format: "id == %@", job.id as CVarArg)
        request.fetchLimit = 1

        let entity = (try? context.fetch(request))?.first ?? JobEntity(context: context)
        entity.id = job.id
        entity.createdAt = job.createdAt
        entity.state = job.state.rawValue
        entity.photoLocalID = job.photoLocalID
        entity.barcode = job.barcode
        entity.ocrText = try? JSONEncoder().encode(job.ocrText)
        entity.candidateMBIDs = try? JSONEncoder().encode(job.candidateMBIDs)
        entity.chosenMBID = job.chosenMBID
        entity.chosenSpotifyAlbumID = job.chosenSpotifyAlbumID
        entity.addedTrackIDs = try? JSONEncoder().encode(job.addedTrackIDs)
        entity.errorDescription = job.errorDescription

        persistence.save()
    }

    private func persistDedupeEntries(playlistID: String, trackIDs: [String]) {
        guard !trackIDs.isEmpty else { return }
        let context = persistence.container.viewContext

        for trackID in trackIDs {
            let request = NSFetchRequest<DedupeEntity>(entityName: "DedupeEntity")
            request.predicate = NSPredicate(format: "playlistID == %@ AND trackID == %@", playlistID, trackID)
            request.fetchLimit = 1
            if (try? context.fetch(request))?.first != nil {
                continue
            }
            let entity = DedupeEntity(context: context)
            entity.playlistID = playlistID
            entity.trackID = trackID
        }

        persistence.save()
    }

    private static func loadJobs(from persistence: Persistence) -> [Job] {
        let context = persistence.container.viewContext
        let request = NSFetchRequest<JobEntity>(entityName: "JobEntity")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        guard let entities = try? context.fetch(request) else { return [] }
        return entities.compactMap { entity in
            let state = JobState(rawValue: entity.state) ?? .pending
            let ocrText = (entity.ocrText).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
            let candidateMBIDs = (entity.candidateMBIDs).flatMap { try? JSONDecoder().decode([AlbumMatch].self, from: $0) } ?? []
            let addedTrackIDs = (entity.addedTrackIDs).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
            return Job(
                id: entity.id,
                createdAt: entity.createdAt,
                state: state,
                photoLocalID: entity.photoLocalID,
                barcode: entity.barcode,
                ocrText: ocrText,
                candidateMBIDs: candidateMBIDs,
                chosenMBID: entity.chosenMBID,
                chosenSpotifyAlbumID: entity.chosenSpotifyAlbumID,
                addedTrackIDs: addedTrackIDs,
                errorDescription: entity.errorDescription
            )
        }
    }

    private static func loadDedupeSet(from persistence: Persistence) -> Set<String> {
        let context = persistence.container.viewContext
        let request = NSFetchRequest<DedupeEntity>(entityName: "DedupeEntity")
        guard let entities = try? context.fetch(request) else { return [] }
        return Set(entities.map { $0.trackID })
    }
}
