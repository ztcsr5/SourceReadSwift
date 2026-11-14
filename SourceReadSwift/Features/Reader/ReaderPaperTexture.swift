import SwiftUI
import UIKit

enum ReaderPaperTexture {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 16
        cache.totalCostLimit = 16 * 256 * 256 * 4
        return cache
    }()

    static func cachedImage(background: ReaderBackground, night: Bool) -> UIImage? {
        let key = "\(background.rawValue)|\(night)" as NSString
        return cache.object(forKey: key)
    }

    static func loadAsync(background: ReaderBackground, night: Bool) async -> UIImage {
        if let hit = cachedImage(background: background, night: night) {
            return hit
        }
        return await Task.detached(priority: .utility) {
            image(background: background, night: night)
        }.value
    }

    nonisolated static func image(background: ReaderBackground, night: Bool) -> UIImage {
        let key = "\(background.rawValue)|\(night)" as NSString
        if let image = cache.object(forKey: key) { return image }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let size = CGSize(width: 256, height: 256)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let c = renderer.cgContext
            background.uiColor(isNight: night).setFill()
            c.fill(CGRect(origin: .zero, size: size))
            // Deterministic fibre/grain: generated once per style, not per frame.
            var state: UInt64 = 0x51_77_22
            func unit() -> CGFloat {
                state = state &* 6364136223846793005 &+ 1
                return CGFloat((state >> 32) & 0xffff) / 65535
            }
            for i in 0..<6500 {
                let x = unit() * 256, y = unit() * 256
                c.setFillColor(UIColor(white: i % 2 == 0 ? 0 : 1, alpha: night ? 0.035 : 0.065).cgColor)
                c.fillEllipse(in: CGRect(x: x, y: y, width: 0.4 + unit() * 1.1, height: 0.4 + unit() * 0.8))
            }
            c.setStrokeColor(UIColor(white: night ? 1 : 0, alpha: night ? 0.025 : 0.045).cgColor)
            c.setLineWidth(0.4)
            for _ in 0..<550 {
                let x = unit() * 256, y = unit() * 256
                c.move(to: CGPoint(x: x, y: y))
                c.addLine(to: CGPoint(x: x + 1 + unit() * 9, y: y + unit() * 2))
                c.strokePath()
            }
            if background == .linen {
                c.setStrokeColor(UIColor(white: night ? 1 : 0, alpha: 0.035).cgColor)
                for n in stride(from: 0, through: 256, by: 3) {
                    c.move(to: CGPoint(x: n, y: 0)); c.addLine(to: CGPoint(x: n, y: 256))
                    c.move(to: CGPoint(x: 0, y: n)); c.addLine(to: CGPoint(x: 256, y: n))
                }
                c.strokePath()
            }
            background.doodlePattern?.draw(in: c, ink: background.uiTextColor(isNight: night), night: night)
        }
        cache.setObject(image, forKey: key, cost: 256 * 256 * 4)
        return image
    }
}

struct ReaderPaperTextureView: View {
    let background: ReaderBackground
    let night: Bool
    @State private var textureImage: UIImage?

    init(background: ReaderBackground, night: Bool) {
        self.background = background
        self.night = night
        _textureImage = State(initialValue: ReaderPaperTexture.cachedImage(background: background, night: night))
    }

    var body: some View {
        if let asset = background.wallpaperAssetName(isNight: night) {
            ReaderIllustratedBackgroundView(
                name: asset,
                paper: background.color(isNight: night),
                night: night,
                preservesNightArtwork: background.hasDedicatedNightAsset
            )
        } else {
            Group {
                if let textureImage {
                    Image(uiImage: textureImage)
                        .resizable(resizingMode: .tile)
                } else {
                    background.color(isNight: night)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .task(id: "\(background.rawValue)|\(night)") {
                if let cached = ReaderPaperTexture.cachedImage(background: background, night: night) {
                    if textureImage !== cached {
                        textureImage = cached
                    }
                    return
                }
                let loaded = await ReaderPaperTexture.loadAsync(background: background, night: night)
                guard !Task.isCancelled else { return }
                textureImage = loaded
            }
        }
    }
}
