import SwiftUI

/// Short-lived references to the existing pipeline's decoded covers, not a second decoder.
/// Only the reading-desk entry and its destinations receive this environment value.
final class ReadingCoverHandoff: ObservableObject {
    private let images = NSCache<NSURL, UIImage>()

    init() {
        images.countLimit = 5
        images.totalCostLimit = 8 * 1024 * 1024
    }

    func retain(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
        images.setObject(image, forKey: url as NSURL, cost: cost)
    }

    func image(for url: URL) -> UIImage? { images.object(forKey: url as NSURL) }
    func clear() { images.removeAllObjects() }
}

private struct ReadingCoverHandoffKey: EnvironmentKey {
    static let defaultValue: ReadingCoverHandoff? = nil
}

extension EnvironmentValues {
    var readingCoverHandoff: ReadingCoverHandoff? {
        get { self[ReadingCoverHandoffKey.self] }
        set { self[ReadingCoverHandoffKey.self] = newValue }
    }
}
