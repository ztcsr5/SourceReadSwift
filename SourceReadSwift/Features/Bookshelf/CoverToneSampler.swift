import UIKit

/// A low-saturation accent derived from an already decoded cover, never a second download.
struct CoverTone: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let vividRed: Double
    let vividGreen: Double
    let vividBlue: Double
}

private final class CachedCoverTone: NSObject {
    let tone: CoverTone?
    init(_ tone: CoverTone?) { self.tone = tone }
}

/// Samples a bounded bitmap off main; image identity follows the shared image cache's lifetime.
final class CoverToneSampler: @unchecked Sendable {
    static let shared = CoverToneSampler()
    private let cache = NSCache<UIImage, CachedCoverTone>()

    init() {
        cache.countLimit = 100
        cache.totalCostLimit = 8 * 1024 * 1024
    }

    func tone(for image: UIImage) async -> CoverTone? {
        if let cached = cache.object(forKey: image) { return cached.tone }
        return await Task.detached(priority: .utility) { [self] in
            let tone = Self.sample(image)
            let bitmapCost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
            cache.setObject(CachedCoverTone(tone), forKey: image, cost: bitmapCost)
            return tone
        }.value
    }

    func hasCachedTone(for image: UIImage) -> Bool { cache.object(forKey: image) != nil }

    private static func sample(_ image: UIImage) -> CoverTone? {
        precondition(!Thread.isMainThread, "Cover sampling must not block scrolling")
        guard let bitmap = image.cgImage else { return nil }
        let edge = 24
        var pixels = [UInt8](repeating: 0, count: edge * edge * 4)
        let didDraw = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: edge, height: edge,
                                          bitsPerComponent: 8, bytesPerRow: edge * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: edge, height: edge))
            return true
        }
        guard didDraw else { return nil }
        var red = 0.0, green = 0.0, blue = 0.0, count = 0.0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(pixels[offset]) / (255 * alpha)
            let g = Double(pixels[offset + 1]) / (255 * alpha)
            let b = Double(pixels[offset + 2]) / (255 * alpha)
            let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
            guard luminance > 0.06, luminance < 0.96 else { continue }
            red += r; green += g; blue += b; count += 1
        }
        guard count > 0 else { return nil }
        let average = UIColor(red: red / count, green: green / count, blue: blue / count, alpha: 1)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard average.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return nil }
        let muted = UIColor(hue: hue, saturation: min(saturation, 0.22), brightness: 0.72, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        guard muted.getRed(&r, green: &g, blue: &b, alpha: &alpha) else { return nil }
        let vivid = UIColor(hue: hue, saturation: min(saturation, 0.65), brightness: 0.70, alpha: 1)
        var vr: CGFloat = 0, vg: CGFloat = 0, vb: CGFloat = 0
        guard vivid.getRed(&vr, green: &vg, blue: &vb, alpha: &alpha) else { return nil }
        return CoverTone(red: Double(r), green: Double(g), blue: Double(b),
                         vividRed: Double(vr), vividGreen: Double(vg), vividBlue: Double(vb))
    }
}
