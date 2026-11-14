import Combine
import ImageIO
import SwiftUI
import UIKit

enum CustomThemeFontStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case songti
    case calligraphy
    case rounded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "系统默认"
        case .songti: return "雅致宋体"
        case .calligraphy: return "书法题韵"
        case .rounded: return "柔和圆体"
        }
    }

    var fontDesign: Font.Design {
        switch self {
        case .system: return .default
        case .songti: return .serif
        case .calligraphy: return .serif
        case .rounded: return .rounded
        }
    }

    var displayFontName: String? {
        switch self {
        case .system, .rounded: return nil
        case .songti: return "ReadingDeskSong-Regular"
        case .calligraphy: return "MaShanZheng-Regular"
        }
    }
}

enum CustomThemeBackdropKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case solid
    case gradient
    case photo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: return "纯色"
        case .gradient: return "双色渐变"
        case .photo: return "自选图片"
        }
    }
}

enum CustomThemeCardSurface: String, CaseIterable, Identifiable, Codable, Sendable {
    case paper
    case glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .paper: return "温润纸面"
        case .glass: return "通透玻璃"
        }
    }
}

struct CustomThemePreset: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var backdropKind: CustomThemeBackdropKind
    var lightSolidHex: UInt32
    var darkSolidHex: UInt32
    var gradientStartHex: UInt32
    var gradientEndHex: UInt32
    var darkGradientStartHex: UInt32
    var darkGradientEndHex: UInt32
    var gradientAngleDegrees: Double
    var lightImageFilename: String?
    var darkImageFilename: String?
    var blurRadius: Double
    var lightDimming: Double
    var darkDimming: Double
    var lightAccentHex: UInt32
    var lightSecondaryHex: UInt32
    var darkAccentHex: UInt32
    var darkSecondaryHex: UInt32
    var lightBackgroundHex: UInt32
    var darkBackgroundHex: UInt32
    var lightCardHex: UInt32
    var darkCardHex: UInt32
    var cornerRadius: Double
    var cardSurface: CustomThemeCardSurface
    var cardOpacity: Double
    var fontStyle: CustomThemeFontStyle

    static func defaultPreset(name: String = "我的方案 1") -> CustomThemePreset {
        CustomThemePreset(
            id: UUID(),
            name: name,
            backdropKind: .gradient,
            lightSolidHex: 0xF5F3EE,
            darkSolidHex: 0x15181C,
            gradientStartHex: 0xF4F7F9,
            gradientEndHex: 0xEFEAE4,
            darkGradientStartHex: 0x121923,
            darkGradientEndHex: 0x1B1722,
            gradientAngleDegrees: 145,
            lightImageFilename: nil,
            darkImageFilename: nil,
            blurRadius: 0,
            lightDimming: 0.06,
            darkDimming: 0.42,
            lightAccentHex: 0x2F5E8C,
            lightSecondaryHex: 0x8F5E38,
            darkAccentHex: 0x99C8F5,
            darkSecondaryHex: 0xECC098,
            lightBackgroundHex: 0xF4F5F2,
            darkBackgroundHex: 0x13161B,
            lightCardHex: 0xFFFFFF,
            darkCardHex: 0x1F242C,
            cornerRadius: 16,
            cardSurface: .glass,
            cardOpacity: 0.90,
            fontStyle: .system
        )
    }
}

struct ExtractedThemePalette: Equatable, Sendable {
    let lightAccentHex: UInt32
    let lightSecondaryHex: UInt32
    let lightBackgroundHex: UInt32
    let lightCardHex: UInt32
    let darkAccentHex: UInt32
    let darkSecondaryHex: UInt32
    let darkBackgroundHex: UInt32
    let darkCardHex: UInt32
}

enum CustomThemePaletteExtractor {
    static func extractHarmoniousPalette(from image: UIImage) -> ExtractedThemePalette {
        let samples = samplePixels(from: image)
        guard !samples.isEmpty else {
            let fallback = CustomThemePreset.defaultPreset()
            return ExtractedThemePalette(
                lightAccentHex: fallback.lightAccentHex,
                lightSecondaryHex: fallback.lightSecondaryHex,
                lightBackgroundHex: fallback.lightBackgroundHex,
                lightCardHex: fallback.lightCardHex,
                darkAccentHex: fallback.darkAccentHex,
                darkSecondaryHex: fallback.darkSecondaryHex,
                darkBackgroundHex: fallback.darkBackgroundHex,
                darkCardHex: fallback.darkCardHex
            )
        }

        var avgR: Double = 0, avgG: Double = 0, avgB: Double = 0
        var bestAccent = (score: -1.0, r: 0.25, g: 0.36, b: 0.62)
        var secondAccent = (score: -1.0, r: 0.55, g: 0.38, b: 0.26)

        for (r, g, b) in samples {
            avgR += r; avgG += g; avgB += b
            let maxC = max(r, max(g, b)), minC = min(r, min(g, b))
            let sat = maxC > 0.001 ? (maxC - minC) / maxC : 0
            let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let vibrancy = sat * (1.0 - abs(luma - 0.45))
            if vibrancy > bestAccent.score {
                secondAccent = bestAccent
                bestAccent = (vibrancy, r, g, b)
            } else if vibrancy > secondAccent.score {
                let dr = r - bestAccent.r, dg = g - bestAccent.g, db = b - bestAccent.b
                if (dr * dr + dg * dg + db * db) > 0.08 {
                    secondAccent = (vibrancy, r, g, b)
                }
            }
        }

        let count = Double(samples.count)
        avgR /= count; avgG /= count; avgB /= count

        // Fallback if grayscale photo
        if bestAccent.score < 0.08 {
            bestAccent = (0.5, 0.22, 0.42, 0.48)
            secondAccent = (0.4, 0.52, 0.38, 0.24)
        }
        if secondAccent.score < 0.05 {
            secondAccent = (0.4, 1.0 - bestAccent.r * 0.5, 0.65, 1.0 - bestAccent.b * 0.4)
        }

        // Light tint paper from image average blended 90% with warm off-white
        let lBgHex = rgbHex(r: 0.90 + avgR * 0.08, g: 0.90 + avgG * 0.08, b: 0.90 + avgB * 0.08)
        let lCardHex: UInt32 = 0xFFFFFF
        // Dark ink canvas from image average blended softly into deep slate
        let dBgHex = rgbHex(r: 0.05 + avgR * 0.07, g: 0.055 + avgG * 0.07, b: 0.07 + avgB * 0.08)
        let dCardHex = rgbHex(r: 0.09 + avgR * 0.09, g: 0.10 + avgG * 0.09, b: 0.12 + avgB * 0.10)

        let lightAccent = tuneForContrast(r: bestAccent.r, g: bestAccent.g, b: bestAccent.b,
                                          over: lCardHex, targetRatio: 5.0, preferDarker: true)
        let lightSecondary = tuneForContrast(r: secondAccent.r, g: secondAccent.g, b: secondAccent.b,
                                             over: lCardHex, targetRatio: 4.5, preferDarker: true)
        let darkAccent = tuneForContrast(r: bestAccent.r, g: bestAccent.g, b: bestAccent.b,
                                         over: dCardHex, targetRatio: 5.2, preferDarker: false)
        let darkSecondary = tuneForContrast(r: secondAccent.r, g: secondAccent.g, b: secondAccent.b,
                                            over: dCardHex, targetRatio: 4.6, preferDarker: false)

        return ExtractedThemePalette(
            lightAccentHex: lightAccent,
            lightSecondaryHex: lightSecondary,
            lightBackgroundHex: lBgHex,
            lightCardHex: lCardHex,
            darkAccentHex: darkAccent,
            darkSecondaryHex: darkSecondary,
            darkBackgroundHex: dBgHex,
            darkCardHex: dCardHex
        )
    }

    private static func samplePixels(from image: UIImage) -> [(Double, Double, Double)] {
        guard let cgImage = image.cgImage else { return [] }
        let side = 24
        var buffer = [UInt8](repeating: 0, count: side * side * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &buffer, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return [] }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        var out: [(Double, Double, Double)] = []
        out.reserveCapacity(side * side)
        for i in stride(from: 0, to: buffer.count, by: 4) {
            out.append((Double(buffer[i]) / 255.0, Double(buffer[i + 1]) / 255.0, Double(buffer[i + 2]) / 255.0))
        }
        return out
    }

    private static func tuneForContrast(
        r: Double, g: Double, b: Double,
        over background: UInt32,
        targetRatio: Double,
        preferDarker: Bool
    ) -> UInt32 {
        var cr = r, cg = g, cb = b
        for step in 0...24 {
            let candidate = rgbHex(r: cr, g: cg, b: cb)
            if contrastRatio(candidate, background) >= targetRatio {
                return candidate
            }
            let factor = Double(step + 1) / 24.0
            if preferDarker {
                cr = r * (1.0 - factor * 0.78)
                cg = g * (1.0 - factor * 0.78)
                cb = b * (1.0 - factor * 0.78)
            } else {
                cr = r + (0.94 - r) * factor * 0.85
                cg = g + (0.95 - g) * factor * 0.85
                cb = b + (0.97 - b) * factor * 0.85
            }
        }
        return preferDarker ? 0x1E2631 : 0xD2DDF0
    }

    private static func rgbHex(r: Double, g: Double, b: Double) -> UInt32 {
        let rb = UInt32((min(max(r, 0), 1) * 255).rounded())
        let gb = UInt32((min(max(g, 0), 1) * 255).rounded())
        let bb = UInt32((min(max(b, 0), 1) * 255).rounded())
        return (rb << 16) | (gb << 8) | bb
    }

    static func contrastRatio(_ fg: UInt32, _ bg: UInt32) -> Double {
        let a = luminance(fg), b = luminance(bg)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func luminance(_ hex: UInt32) -> Double {
        let components = [16, 8, 0].map { shift -> Double in
            let v = Double((hex >> shift) & 255) / 255.0
            return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return components[0] * 0.2126 + components[1] * 0.7152 + components[2] * 0.0722
    }
}

struct CustomThemeSnapshot: Sendable {
    let preset: CustomThemePreset
}

@MainActor
final class AppCustomThemeStore: ObservableObject {
    static let shared = AppCustomThemeStore()

    static let presetsKey = "settings.customThemePresets.v1"
    static let activePresetKey = "settings.activeCustomThemeID"

    @Published private(set) var presets: [CustomThemePreset] = []
    @Published var activePresetID: UUID

    private static let lock = NSLock()
    private nonisolated(unsafe) static var cachedSnapshot = CustomThemeSnapshot(preset: .defaultPreset())
    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 12
        return cache
    }()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let loaded = Self.loadPresets(from: defaults)
        if loaded.isEmpty {
            let initial = CustomThemePreset.defaultPreset()
            self.presets = [initial]
            self.activePresetID = initial.id
            Self.persist(presets: [initial], activeID: initial.id, into: defaults)
        } else {
            self.presets = loaded
            if let savedID = defaults.string(forKey: Self.activePresetKey),
               let uuid = UUID(uuidString: savedID),
               loaded.contains(where: { $0.id == uuid }) {
                self.activePresetID = uuid
            } else {
                self.activePresetID = loaded[0].id
            }
        }
        refreshSnapshot()
    }

    nonisolated static var currentPreset: CustomThemePreset {
        lock.withLock { cachedSnapshot.preset }
    }

    var activePreset: CustomThemePreset {
        presets.first(where: { $0.id == activePresetID }) ?? presets.first ?? .defaultPreset()
    }

    func selectPreset(_ id: UUID) {
        guard presets.contains(where: { $0.id == id }) else { return }
        activePresetID = id
        defaults.set(id.uuidString, forKey: Self.activePresetKey)
        refreshSnapshot()
        bumpRevision()
    }

    func updateActive(_ mutate: (inout CustomThemePreset) -> Void) {
        guard let index = presets.firstIndex(where: { $0.id == activePresetID }) else { return }
        var updated = presets[index]
        mutate(&updated)
        presets[index] = updated
        Self.persist(presets: presets, activeID: activePresetID, into: defaults)
        refreshSnapshot()
        bumpRevision()
    }

    @discardableResult
    func createPreset(name: String? = nil, cloningCurrent: Bool = false) -> CustomThemePreset {
        var next = cloningCurrent ? activePreset : CustomThemePreset.defaultPreset(name: "方案 \(presets.count + 1)")
        next.id = UUID()
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            next.name = name
        } else if cloningCurrent {
            next.name = "\(activePreset.name) 副本"
        }
        presets.append(next)
        activePresetID = next.id
        Self.persist(presets: presets, activeID: activePresetID, into: defaults)
        refreshSnapshot()
        bumpRevision()
        return next
    }

    func deletePreset(_ id: UUID) {
        guard presets.count > 1, let index = presets.firstIndex(where: { $0.id == id }) else { return }
        let removed = presets.remove(at: index)
        cleanupUnusedImages(for: [removed.lightImageFilename, removed.darkImageFilename])
        if activePresetID == id {
            activePresetID = presets[0].id
        }
        Self.persist(presets: presets, activeID: activePresetID, into: defaults)
        refreshSnapshot()
        bumpRevision()
    }

    func saveBackgroundImage(data: Data, isDarkVariant: Bool, maxPixelSize: CGFloat = 1536) async -> String? {
        let storageDir = Self.assetDirectoryURL()
        let filename = "theme-\(isDarkVariant ? "night" : "day")-\(UUID().uuidString).jpg"
        let destination = storageDir.appendingPathComponent(filename)

        let downsampled = await Task.detached(priority: .utility) { () -> UIImage? in
            Self.createDirectoryIfNeeded(storageDir)
            guard let downsampledImage = Self.downsample(data: data, maxPixelSize: maxPixelSize),
                  let jpeg = downsampledImage.jpegData(compressionQuality: 0.86) else { return nil }
            try? jpeg.write(to: destination, options: .atomic)
            return downsampledImage
        }.value

        guard let downsampled else { return nil }
        Self.imageCache.setObject(downsampled, forKey: Self.cacheKey(filename: filename, blur: 0))

        updateActive { preset in
            if isDarkVariant {
                preset.darkImageFilename = filename
            } else {
                preset.lightImageFilename = filename
            }
            preset.backdropKind = .photo
        }
        return filename
    }

    nonisolated static func cachedImage(filename: String?, blurRadius: Double) -> UIImage? {
        guard let filename else { return nil }
        let quantizedBlur = Int((max(0, min(blurRadius, 24)) / 2.0).rounded()) * 2
        if let hit = imageCache.object(forKey: cacheKey(filename: filename, blur: quantizedBlur)) {
            return hit
        }
        if quantizedBlur == 0 {
            return nil
        }
        return nil
    }

    nonisolated static func loadImage(filename: String?, blurRadius: Double) async -> UIImage? {
        guard let filename else { return nil }
        let quantizedBlur = Int((max(0, min(blurRadius, 24)) / 2.0).rounded()) * 2
        let key = cacheKey(filename: filename, blur: quantizedBlur)
        if let hit = imageCache.object(forKey: key) {
            return hit
        }
        let url = assetDirectoryURL().appendingPathComponent(filename)
        let loaded: UIImage? = await Task.detached(priority: .utility) {
            let baseKey = cacheKey(filename: filename, blur: 0)
            let baseImage: UIImage
            if let existingBase = imageCache.object(forKey: baseKey) {
                baseImage = existingBase
            } else if let data = try? Data(contentsOf: url),
                      let decoded = downsample(data: data, maxPixelSize: 1536) {
                imageCache.setObject(decoded, forKey: baseKey)
                baseImage = decoded
            } else {
                return nil
            }
            if quantizedBlur <= 0 { return baseImage }
            let blurred = applyGaussianBlur(to: baseImage, radius: CGFloat(quantizedBlur)) ?? baseImage
            imageCache.setObject(blurred, forKey: key)
            return blurred
        }.value
        return loaded
    }

    private func refreshSnapshot() {
        let active = activePreset
        Self.lock.withLock {
            Self.cachedSnapshot = CustomThemeSnapshot(preset: active)
        }
    }

    private func bumpRevision() {
        defaults.set(defaults.integer(forKey: "settings.appearanceRevision") + 1,
                     forKey: "settings.appearanceRevision")
    }

    private func cleanupUnusedImages(for candidates: [String?]) {
        let referenced = Set(presets.flatMap { [$0.lightImageFilename, $0.darkImageFilename] }.compactMap { $0 })
        for case let name? in candidates where !referenced.contains(name) {
            try? FileManager.default.removeItem(at: Self.assetDirectoryURL().appendingPathComponent(name))
        }
    }

    private static func loadPresets(from defaults: UserDefaults) -> [CustomThemePreset] {
        guard let data = defaults.data(forKey: presetsKey),
              let decoded = try? JSONDecoder().decode([CustomThemePreset].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func persist(presets: [CustomThemePreset], activeID: UUID, into defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(presets) {
            defaults.set(data, forKey: presetsKey)
        }
        defaults.set(activeID.uuidString, forKey: activePresetKey)
    }

    private nonisolated static func assetDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CustomThemeAssets", isDirectory: true)
    }

    private nonisolated static func createDirectoryIfNeeded(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private nonisolated static func cacheKey(filename: String, blur: Int) -> NSString {
        "\(filename)#b\(blur)" as NSString
    }

    private nonisolated static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else { return nil }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }

    private nonisolated static func applyGaussianBlur(to image: UIImage, radius: CGFloat) -> UIImage? {
        guard radius > 0, let ciInput = CIImage(image: image) else { return image }
        let clamped = ciInput.clampedToExtent()
        guard let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        filter.setValue(clamped, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        guard let output = filter.outputImage?.cropped(to: ciInput.extent) else { return image }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cg = context.createCGImage(output, from: ciInput.extent) else { return image }
        return UIImage(cgImage: cg)
    }
}
