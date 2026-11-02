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

    func image(_ name: String) -> UIImage? { prepared[name]?.cover }
    func haze(_ name: String) -> UIImage? { prepared[name]?.haze }

    func prepare() async {
        guard prepared.isEmpty else { return }
        let bundle = Bundle.main
        let rendered = await Task.detached(priority: .userInitiated) {
            let context = CIContext(options: [.cacheIntermediates: false])
            var result: [String: PreparedArtwork] = [:]
            let names = Set(LabBook.samples.map(\.artwork) + ReferenceMedia.samples.flatMap { [$0.poster, $0.backdrop, $0.logo] }.filter { !$0.isEmpty })
            for name in names {
                guard let original = UIImage(named: name, in: bundle, compatibleWith: nil),
                      let cg = original.cgImage else { continue }
                let image = Self.thumbnail(cg, maximum: 1200)
                let small = Self.thumbnail(cg, maximum: 96)
                let input = CIImage(cgImage: small)
                let blurred = input.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 9])
                let haze = context.createCGImage(blurred, from: input.extent).map { UIImage(cgImage: $0) }
                result[name] = PreparedArtwork(cover: UIImage(cgImage: image), haze: haze)
            }
            return result
        }.value
        guard !Task.isCancelled else { return }
        prepared = rendered
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
                if book.id == "tide", showsTitle {
                    LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.title).font(.system(size: max(14, proxy.size.width * 0.14), weight: .semibold, design: .serif))
                        Text("闻屿 / 原创演示").font(.system(size: max(8, proxy.size.width * 0.045)))
                    }.foregroundStyle(.white).padding(max(10, proxy.size.width * 0.08))
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
