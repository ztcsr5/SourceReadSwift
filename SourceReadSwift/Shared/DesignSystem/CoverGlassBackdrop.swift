import CoreImage
import SwiftUI
import UIKit

/// Publishes one prepared background, never the whole shelf or scroll position.
@MainActor
final class CoverGlassBackdropStore: ObservableObject {
    static let shared = CoverGlassBackdropStore()
    @Published private(set) var image: UIImage?
    private var source: URL?
    private var isEnabled = false
    private var request: Task<Void, Never>?
    private var generation = 0
    private let render: @Sendable (URL) async -> UIImage?

    init(render: @escaping @Sendable (URL) async -> UIImage? = { await CoverGlassBackdropStore.preparedImage(for: $0) }) {
        self.render = render
    }

    nonisolated static func preparedImage(for url: URL) async -> UIImage? {
        await CoverGlassRenderer.shared.image(for: url)
    }

    func setSource(_ url: URL?) {
        guard source != url else { return }
        source = url
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        refresh()
    }

    private func refresh() {
        request?.cancel()
        generation &+= 1
        guard isEnabled, let source else {
            image = nil
            return
        }
        let expectedGeneration = generation
        let render = render
        request = Task(priority: .utility) { [weak self] in
            let prepared = await render(source)
            guard !Task.isCancelled, let self, self.generation == expectedGeneration else { return }
            // Unavailable covers fall back to the neutral canvas, not another book's colors.
            self.image = prepared
        }
    }
}

private actor CoverGlassRenderer {
    static let shared = CoverGlassRenderer()
    private let cache = NSCache<NSURL, UIImage>()
    private lazy var context = CIContext(options: [.useSoftwareRenderer: false])

    init() {
        cache.countLimit = 4
        cache.totalCostLimit = 1024 * 1024
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let cover = await RemoteImageLoader.shared.image(for: url, maxPixelSize: 96, reuseCoverBytes: true),
              !Task.isCancelled, let input = CIImage(image: cover),
              let filter = CIFilter(name: "CIGaussianBlur") else { return nil }
        filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        // At 96 px this removes detail before the bitmap is stretched to page size.
        filter.setValue(16, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage,
              let pixels = context.createCGImage(output, from: input.extent) else { return nil }
        let prepared = UIImage(cgImage: pixels)
        cache.setObject(prepared, forKey: url as NSURL, cost: pixels.bytesPerRow * pixels.height)
        return prepared
    }
}

struct CoverGlassBackdrop: View {
    @ObservedObject var backdrop = CoverGlassBackdropStore.shared
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { geometry in
            if !reducesTransparency, contrast != .increased {
                if let image = backdrop.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .overlay {
                            // Lift only deep shadows; a stronger white veil also erases midtones.
                            if scheme == .light { Color(white: 0.39).blendMode(.lighten) }
                        }
                        .overlay { paperVeil }
                } else { ForestGlassBackdrop() }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var paperVeil: LinearGradient {
        let dark = scheme == .dark
        let paper: Color = dark ? .black : .white
        return LinearGradient(stops: [
            .init(color: paper.opacity(dark ? 0.64 : 0.24), location: 0),
            .init(color: paper.opacity(dark ? 0.66 : 0.28), location: 0.51),
            .init(color: paper.opacity(dark ? 0.76 : 0.68), location: 0.80),
            .init(color: paper.opacity(dark ? 0.82 : 0.84), location: 1)
        ], startPoint: .top, endPoint: .bottom)
    }
}

struct CoverGlassInk: ViewModifier {
    let theme: AppVisualTheme

    @ViewBuilder func body(content: Content) -> some View {
        if theme.usesTintedPaper {
            content.foregroundStyle(theme.primaryInk, theme.secondaryInk)
        } else {
            content
        }
    }
}
