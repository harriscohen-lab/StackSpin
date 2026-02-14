import CoreData
import Foundation
import Vision

final class FeaturePrintMatcher {
    private let persistence: Persistence

    init(persistence: Persistence = .shared) {
        self.persistence = persistence
    }

    func nearestNeighborDistance(query: CGImage) async throws -> (mbid: String, distance: Float)? {
        #if targetEnvironment(simulator)
        return nil
        #else
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: query, options: [:])
        try handler.perform([request])
        guard let queryObservation = request.results?.first as? VNFeaturePrintObservation else { return nil }

        let context = persistence.container.viewContext
        let fetch = NSFetchRequest<AlbumCacheItemEntity>(entityName: "AlbumCacheItemEntity")
        let items = try context.fetch(fetch)
        var best: (String, Float)?
        for item in items {
            guard
                let data = item.featurePrintData,
                let storedObservation = decodeFeaturePrintObservation(from: data)
            else {
                continue
            }

            var distance: Float = 0
            try queryObservation.computeDistance(&distance, to: storedObservation)
            if best == nil || distance < best!.1 {
                best = (item.mbid ?? "", distance)
            }
        }
        return best
        #endif
    }

    func storeFeaturePrint(_ image: CGImage, mbid: String) async {
        #if targetEnvironment(simulator)
        return
        #else
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            guard
                let observation = request.results?.first as? VNFeaturePrintObservation,
                let data = encodeFeaturePrintObservation(observation)
            else {
                return
            }

            let context = persistence.container.viewContext
            let entity = AlbumCacheItemEntity(context: context)
            entity.mbid = mbid
            entity.lastUsedAt = Date()
            entity.featurePrintData = data
            persistence.save()
        } catch {
            NSLog("Feature print store error: \(error)")
        }
        #endif
    }

    private func encodeFeaturePrintObservation(_ observation: VNFeaturePrintObservation) -> Data? {
        do {
            return try NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
        } catch {
            NSLog("Feature print encode error: \(error)")
            return nil
        }
    }

    private func decodeFeaturePrintObservation(from data: Data) -> VNFeaturePrintObservation? {
        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
        } catch {
            NSLog("Feature print decode error: \(error)")
            return nil
        }
    }
}
