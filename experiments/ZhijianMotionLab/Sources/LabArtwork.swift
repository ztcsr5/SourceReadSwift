import SwiftUI
import ImageIO
import CoreImage

private struct PreparedArtwork {
    let cover: UIImage
    let haze: UIImage?
}

/// Decode and preblur once off main, never a live full-screen Gaussian blur.
@MainActor final class LabArtwork: ObservableObject {
    @Published private var prepared: [String: PreparedArtwork] = [:]
    @Published private(set) var isReady = false
    private var isPreparing = false
    private var isComplete = false

    func image(_ name: String) -> UIImage? { prepared[name]?.cover }
    func haze(_ name: String) -> UIImage? { prepared[name]?.haze }

    func prepare() async {
        guard !isComplete, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }
        let posters = Set(LabBook.samples.map(\.artwork))
        let first = await Task.detached(priority: .userInitiated) {
            Self.render(posters, hazes: [])
        }.value
        guard !Task.isCancelled else { return }
        prepared = first
        isReady = true

        let legacy = Set(LabBook.samples.map(\.artwork))
        let remaining = legacy
        let rest = await Task.detached(priority: .utility) {
            Self.render(remaining, hazes: legacy)
        }.value
        guard !Task.isCancelled else { return }
        prepared.merge(rest) { _, complete in complete }
        isComplete = true
    }

    nonisolated private static func render(_ names: Set<String>, hazes: Set<String>) -> [String: PreparedArtwork] {
        let context = hazes.isEmpty ? nil : CIContext(options: [.cacheIntermediates: false])
        var result: [String: PreparedArtwork] = [:]
        for name in names {
            guard let original = UIImage(named: name, in: Bundle.main, compatibleWith: nil), let cg = original.cgImage else { continue }
            let image = Self.thumbnail(cg, maximum: 1200)
            var haze: UIImage?
            if hazes.contains(name), let context {
                let small = Self.thumbnail(cg, maximum: 96)
                let input = CIImage(cgImage: small)
                let blurred = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 9])
                haze = context.createCGImage(blurred, from: input.extent).map { UIImage(cgImage: $0) }
            }
            result[name] = PreparedArtwork(cover: UIImage(cgImage: image), haze: haze)
        }
        return result
    }

    nonisolated private static func thumbnail(_ image: CGImage, maximum: CGFloat) -> CGImage {
        let scale = min(maximum / CGFloat(max(image.width, image.height)), 1)
        guard let context = CGContext(data: nil, width: max(1, Int(CGFloat(image.width) * scale)),
                                      height: max(1, Int(CGFloat(image.height) * scale)), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return context.makeImage() ?? image
    }
}

struct LabCover: View {
    @EnvironmentObject private var artwork: LabArtwork
    let book: LabBook
    var showsTitle = true
    var radius: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                if let image = artwork.image(book.artwork) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [.indigo, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                LinearGradient(colors: [.black.opacity(0.3), .clear, .white.opacity(0.15), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 9)
            }
            .frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(0.22), lineWidth: 0.7))
        .accessibilityLabel("《\(book.title)》封面")
    }
}
