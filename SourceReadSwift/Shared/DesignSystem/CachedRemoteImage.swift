import SwiftUI
import UIKit

/// Lightweight in-memory image loader for scrolling lists and illustrations.
/// Uses `RemoteImageLoader.shared` to share decoded bitmaps across views,
/// text layout attachments, and custom source header requests.
struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    let contentMode: ContentMode
    let headers: [String: String]
    /// Optional decode ceiling in pixels. Cover thumbnails pass their display
    /// size × screen scale so a 2000 px source never becomes a 2000 px texture
    /// in a 70 pt shelf cell.
    let maxPixelSize: CGFloat?
    let reuseCoverBytes: Bool
    let onSizeChange: ((CGSize) -> Void)?
    let onImageLoad: ((UIImage?) -> Void)?
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var loadedIdentifier: String?

    init(
        url: URL?,
        contentMode: ContentMode = .fill,
        headers: [String: String] = [:],
        maxPixelSize: CGFloat? = nil,
        reuseCoverBytes: Bool = false,
        onSizeChange: ((CGSize) -> Void)? = nil,
        onImageLoad: ((UIImage?) -> Void)? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.headers = headers
        self.maxPixelSize = maxPixelSize
        self.reuseCoverBytes = reuseCoverBytes
        self.onSizeChange = onSizeChange
        self.onImageLoad = onImageLoad
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let rendered = readyBitmap {
                Image(uiImage: rendered)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: taskIdentifier) {
            await loadImage()
        }
    }

    private var readyBitmap: UIImage? {
        if let image, loadedIdentifier == taskIdentifier { return image }
        // A hot, correctly sized cover wins the very first frame, before the
        // navigation handoff's lower-resolution placeholder has a chance to draw.
        guard reuseCoverBytes, headers.isEmpty, let url else { return nil }
        return RemoteImageLoader.shared.cachedImage(for: url, maxPixelSize: maxPixelSize, reuseCoverBytes: true)
    }

    private var taskIdentifier: String {
        guard let url else { return "" }
        let sizeKey = maxPixelSize.map { "px\(Int($0.rounded()))" } ?? "full"
        if headers.isEmpty {
            return (reuseCoverBytes ? "cover|" : "image|") + url.absoluteString + "#" + sizeKey
        }
        let headerKey = headers
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
        return url.absoluteString + "#" + headerKey + "#" + sizeKey
    }

    private func loadImage() async {
        guard !Task.isCancelled else { return }
        guard let url else {
            await MainActor.run {
                image = nil
                loadedIdentifier = nil
                onImageLoad?(nil)
                onSizeChange?(.zero)
            }
            return
        }

        if let cached = RemoteImageLoader.shared.cachedImage(for: url, maxPixelSize: maxPixelSize, reuseCoverBytes: reuseCoverBytes && headers.isEmpty) {
            await MainActor.run {
                guard !Task.isCancelled else { return }
                image = cached
                loadedIdentifier = taskIdentifier
                onSizeChange?(cached.size)
                onImageLoad?(cached)
            }
            return
        }

        await MainActor.run {
            guard !Task.isCancelled else { return }
            onImageLoad?(nil)
        }

        let loaded = await RemoteImageLoader.shared.image(
            for: url,
            headers: headers,
            maxPixelSize: maxPixelSize,
            reuseCoverBytes: reuseCoverBytes
        )
        guard let loaded, !Task.isCancelled else { return }
        await MainActor.run {
            guard !Task.isCancelled else { return }
            image = loaded
            loadedIdentifier = taskIdentifier
            onSizeChange?(loaded.size)
            onImageLoad?(loaded)
        }
    }
}
