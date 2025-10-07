import CoreData
import Foundation
import Vision

final class FeaturePrintMatcher {
    private let persistence: Persistence

    init(persistence: Persistence = .shared) {
        self.persistence = persistence
    }

    func nearestNeighborDistance(query: CGImage) async throws -> (mbid: String, distance: Float)? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: query, options: [:])
        try handler.perform([request])
        guard let queryObservation = request.results?.first else { return nil }

        let context = persistence.container.viewContext
        let fetch = NSFetchRequest<AlbumCacheItemEntity>(entityName: "AlbumCacheItem")
        let items = try context.fetch(fetch)
        var best: (String, Float)?
        for item in items {
            guard let data = item.featurePrintData else { continue }
            let storedObservation = try VNFeaturePrintObservation(data: data)
            var distance: Float = 0
            try queryObservation.computeDistance(&distance, to: storedObservation)
            if best == nil || distance < best!.1 {
                best = (item.mbid ?? "", distance)
            }
        }
        return best
    }

    func storeFeaturePrint(_ image: CGImage, mbid: String) async {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return }
            let data = observation.dataRepresentation()
            let context = persistence.container.viewContext
            let entity = AlbumCacheItemEntity(context: context)
            entity.mbid = mbid
            entity.lastUsedAt = Date()
            entity.featurePrintData = data
            persistence.save()
        } catch {
            NSLog("Feature print store error: \(error)")
        }
    }
}
