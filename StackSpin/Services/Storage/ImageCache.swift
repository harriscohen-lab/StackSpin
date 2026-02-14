import Foundation
import UIKit

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private let directory: URL
    private let maxProcessingDimension: CGFloat = 1600

    private init() {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        directory = url.appendingPathComponent("StackSpinImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(forKey key: String) -> UIImage? {
        if let image = cache.object(forKey: key as NSString) {
            return image
        }
        let url = directory.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    func store(image: UIImage, forKey key: String) {
        let processingImage = resizedForProcessing(image)
        cache.setObject(processingImage, forKey: key as NSString)
        let url = directory.appendingPathComponent(key)
        if let data = processingImage.jpegData(compressionQuality: 0.8) {
            try? data.write(to: url)
        }
    }

    private func resizedForProcessing(_ image: UIImage) -> UIImage {
        let maxInputDimension = max(image.size.width, image.size.height)
        guard maxInputDimension > maxProcessingDimension else {
            return image
        }

        let scale = maxProcessingDimension / maxInputDimension
        let targetSize = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
