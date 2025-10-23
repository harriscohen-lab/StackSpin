import Foundation
import UIKit

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private let directory: URL

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
        cache.setObject(image, forKey: key as NSString)
        let url = directory.appendingPathComponent(key)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: url)
        }
    }
}
