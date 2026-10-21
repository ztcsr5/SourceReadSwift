import SwiftUI
import UIKit

/// Lightweight in-memory image loader for scrolling lists and illustrations.
/// Uses `RemoteImageLoader.shared` to share decoded bitmaps across views,
/// text layout attachments, and custom source header requests.
struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    let contentMode: ContentMode
    let headers: [String: String]
    let onSizeChange: ((CGSize) -> Void)?
    let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(
        url: URL?,
        contentMode: ContentMode = .fill,
        headers: [String: String] = [:],
        onSizeChange: ((CGSize) -> Void)? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.headers = headers
        self.onSizeChange = onSizeChange
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
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

    private var taskIdentifier: String {
        guard let url else { return "" }
        if headers.isEmpty {
            return url.absoluteString
        }
        return url.absoluteString + "#" + headers.keys.sorted().joined(separator: ",")
    }

    private func loadImage() async {
        guard let url else {
            await MainActor.run {
                image = nil
                onSizeChange?(.zero)
            }
            return
        }

        if let cached = RemoteImageLoader.shared.cachedImage(for: url) {
            await MainActor.run {
                image = cached
                onSizeChange?(cached.size)
            }
            return
        }

        let loaded = await RemoteImageLoader.shared.image(for: url, headers: headers)
        guard let loaded, !Task.isCancelled else { return }
        await MainActor.run {
            image = loaded
            onSizeChange?(loaded.size)
        }
    }
}
