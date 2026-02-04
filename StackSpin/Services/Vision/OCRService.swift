import Foundation
import Vision

final class OCRService {
    func extractText(from cgImage: CGImage) async throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = [Locale.preferredLanguages.first ?? "en_US"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        return observations.flatMap { observation in
            observation.topCandidates(3).map { $0.string }
        }
    }
}
