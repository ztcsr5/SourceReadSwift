import SwiftUI

/// Short-lived references to the existing pipeline's decoded covers, not a second decoder.
/// Scoped to a bookshelf navigation stack; never publishes image arrival to the shelf.
final class ReadingCoverHandoff: ObservableObject {
    private let images = NSCache<NSURL, UIImage>()
    private var nativeCovers: [String: NativeCoverAnchor] = [:]

    init() {
        images.countLimit = 5
        images.totalCostLimit = 8 * 1024 * 1024
    }

    func retain(_ image: UIImage, for url: URL) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
        if let previous = images.object(forKey: url as NSURL)?.cgImage,
           previous.bytesPerRow * previous.height > cost { return }
        images.setObject(image, forKey: url as NSURL, cost: cost)
    }

    func image(for url: URL) -> UIImage? { images.object(forKey: url as NSURL) }

    /// Resolve the correctly sized hot frame before an asynchronous image callback.
    func resolveNativeFrame(for url: URL, maxPixelSize: CGFloat, current: NativeReadingCoverFrame?) -> NativeReadingCoverFrame? {
        let bitmap = RemoteImageLoader.shared.cachedImage(for: url, maxPixelSize: maxPixelSize, reuseCoverBytes: true)
            ?? (current?.url == url ? current?.image : nil) ?? image(for: url)
        return bitmap.map { NativeReadingCoverFrame(url: url, image: $0) }
    }
    /// Capture the current frame at activation, not a later cache replacement.
    func frame(for book: BookshelfBook) -> UIImage? {
        guard let url = CoverURLResolver.url(from: book.coverURL, base: book.bookURL, fallbackBase: book.sourceURL) else { return nil }
        return image(for: url)
    }

    func clear() { images.removeAllObjects() }

    @MainActor func registerNativeCover(_ view: UIView, for sourceID: String) {
        if nativeCovers[sourceID]?.view === view { return }
        nativeCovers = nativeCovers.filter { $0.value.view != nil }
        nativeCovers[sourceID] = NativeCoverAnchor(view)
    }

    @MainActor func nativeCover(for sourceID: String) -> UIView? { nativeCovers[sourceID]?.view }

    @MainActor func removeNativeCover(_ view: UIView, for sourceID: String) {
        guard nativeCovers[sourceID]?.view === view else { return }
        nativeCovers[sourceID] = nil
    }
}

private final class NativeCoverAnchor {
    weak var view: UIView?
    init(_ view: UIView) { self.view = view }
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
