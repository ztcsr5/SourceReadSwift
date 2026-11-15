import Combine
import Foundation
import ImageIO
import UIKit

/// Saves only a bounded, cropped rendition; never copies the original photo or its metadata.
@MainActor
final class PersonalBrandMarkStore: ObservableObject {
    static let shared = PersonalBrandMarkStore()
    nonisolated static let enabledKey = "settings.personalBrandMarkEnabled"
    nonisolated static let frameKey = "settings.personalBrandMarkFrame"

    @Published private(set) var image: UIImage?
    private(set) var isLoaded = false
    private var isUpdating = false
    private let imageURL: URL

    enum Frame: String, CaseIterable, Identifiable, Sendable {
        case full, matte
        var id: String { rawValue }
        var title: String { self == .full ? "满铺" : "纸边留白" }
        var insetFraction: CGFloat { self == .matte ? 0.09 : 0 }
        static var paper: UIColor { .white }
    }

    /// Reuses the prepared photo and the same physical inset as the in-app mark.
    nonisolated static func shortcutIcon(from photo: UIImage, frame: Frame) -> UIImage {
        let edge: CGFloat = 512
        let canvas = CGRect(x: 0, y: 0, width: edge, height: edge)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let inset = edge * frame.insetFraction
        return UIGraphicsImageRenderer(size: canvas.size, format: format).image { context in
            Frame.paper.setFill()
            context.fill(canvas)
            photo.draw(in: canvas.insetBy(dx: inset, dy: inset))
        }
    }

    enum Failure: LocalizedError {
        case busy, invalidPhoto, tooLarge
        var errorDescription: String? {
            switch self {
            case .busy: return "正在保存徽标，请稍后再试。"
            case .invalidPhoto: return "无法读取这张图片，请改选 JPEG、PNG 或 HEIC。"
            case .tooLarge: return "请选择小于 24 MB 的图片。"
            }
        }
    }

    init(directory: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        imageURL = (directory ?? base ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("personal-brand-mark.jpg")
    }

    /// Loads the prepared thumbnail off the UI thread once per process.
    func loadIfNeeded() async {
        guard !isLoaded, !isUpdating else { return }
        isUpdating = true
        defer { isUpdating = false }
        let url = imageURL
        image = await Task.detached(priority: .utility) {
            UIImage(contentsOfFile: url.path)?.preparingForDisplay()
        }.value
        isLoaded = true
    }

    /// Downsamples bad/large inputs before allocation and writes the new image atomically.
    func savePhoto(_ bytes: Data) async throws {
        guard !isUpdating else { throw Failure.busy }
        isUpdating = true
        defer { isUpdating = false }
        let url = imageURL
        image = try await Task.detached(priority: .userInitiated) {
            let prepared = try Self.prepareBrandMark(bytes)
            guard let jpeg = prepared.jpegData(compressionQuality: 0.91) else { throw Failure.invalidPhoto }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try jpeg.write(to: url, options: .atomic)
            return prepared
        }.value
        isLoaded = true
    }

    /// Clears only the app's copy, on the same serialized edit path.
    func removePhoto() async throws {
        guard !isUpdating else { throw Failure.busy }
        isUpdating = true
        defer { isUpdating = false }
        let url = imageURL
        try await Task.detached(priority: .utility) {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }.value
        image = nil
        isLoaded = true
    }

    nonisolated private static func prepareBrandMark(_ bytes: Data) throws -> UIImage {
        guard bytes.count <= 24_000_000 else { throw Failure.tooLarge }
        guard let source = CGImageSourceCreateWithData(bytes as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1024,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw Failure.invalidPhoto }
        let image = UIImage(cgImage: bitmap)
        let edge: CGFloat = 512
        let scale = edge / max(1, min(image.size.width, image.size.height))
        let width = image.size.width * scale
        let height = image.size.height * scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: edge, height: edge), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: edge, height: edge))
            image.draw(in: CGRect(x: (edge - width) / 2, y: (edge - height) / 2, width: width, height: height))
        }
    }
}
