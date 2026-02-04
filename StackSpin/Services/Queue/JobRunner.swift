import BackgroundTasks
import Combine
import Foundation
import UIKit

@MainActor
final class JobRunner: ObservableObject {
    @Published private(set) var jobs: [Job] = []
    private let scheduler: BackgroundScheduler
    private let resolver: Resolver
    private let spotifyAPI: SpotifyAPI
    private var dedupeSet: Set<String> = []

    init(authController: SpotifyAuthController, persistence: Persistence) {
        self.spotifyAPI = SpotifyAPI(authController: authController)
        self.scheduler = BackgroundScheduler()
        self.resolver = Resolver(
            musicBrainz: MusicBrainzAPI(),
            discogs: DiscogsAPI(),
            spotify: spotifyAPI,
            ocr: OCRService(),
            featureMatcher: FeaturePrintMatcher(persistence: persistence),
            persistence: persistence
        )
    }

    func enqueue(job: Job, image: UIImage? = nil) {
        jobs.append(job)
        if let image {
            ImageCache.shared.store(image: image, forKey: job.photoLocalID)
        }
        // TODO(MVP): Persist job and asset reference
        Task { await scheduler.scheduleIfNeeded() }
    }

    func processAll(settings: AppSettings) async {
        for index in jobs.indices {
            await processJob(at: index, settings: settings)
        }
    }

    func resumePendingJobs() async {
        // TODO(MVP): Load jobs from persistence
    }

    private func processJob(at index: Int, settings: AppSettings) async {
        guard jobs.indices.contains(index) else { return }
        var job = jobs[index]
        do {
            job.state = .matching
            try await resolver.resolve(job: &job, settings: settings)
            if let playlist = settings.spotifyPlaylistID, let albumID = job.chosenSpotifyAlbumID {
                let tracks = try await spotifyAPI.albumTracks(albumID: albumID)
                let newURIs = tracks.map { $0.uri }.filter { dedupeSet.insert($0).inserted }
                try await spotifyAPI.addTracks(playlistID: playlist, trackURIs: newURIs)
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
    }
}
