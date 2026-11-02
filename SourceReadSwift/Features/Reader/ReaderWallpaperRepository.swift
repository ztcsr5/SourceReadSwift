import UIKit
import ImageIO

struct ReaderWallpaperSnapshot {
    let image: UIImage
    let adjustment: ReaderWallpaperAdjustment
    var jpeg: Data? = nil
}

/// One atomic envelope commits image and crop together; legacy JPEG stays readable.
struct ReaderWallpaperRepository {
    let rootURL: URL
    var recordURL: URL { rootURL.appendingPathComponent("custom_reader_wallpaper-v2.json") }
    var legacyURL: URL { rootURL.appendingPathComponent("custom_reader_wallpaper.jpg") }
    private let maximumRecordBytes = 12_000_000

    func save(image: UIImage, adjustment: ReaderWallpaperAdjustment) throws -> ReaderWallpaperSnapshot {
        try adjustment.validate()
        let prepared = ReaderWallpaperLayoutPolicy.downsampledImage(image)
        guard let jpeg = prepared.jpegData(compressionQuality: 0.85) else { throw ReaderWallpaperFailure.invalidImage }
        guard jpeg.count <= 8_000_000 else { throw ReaderWallpaperFailure.tooLarge }
        let envelope = Envelope(version: 2, jpeg: jpeg, adjustment: adjustment)
        let encoded = try JSONEncoder().encode(envelope)
        guard encoded.count <= maximumRecordBytes else { throw ReaderWallpaperFailure.tooLarge }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try encoded.write(to: recordURL, options: .atomic)
        return ReaderWallpaperSnapshot(image: prepared, adjustment: adjustment, jpeg: jpeg)
    }

    func saveEncodedJPEG(_ jpeg: Data, adjustment: ReaderWallpaperAdjustment) throws -> ReaderWallpaperSnapshot {
        try adjustment.validate()
        guard !jpeg.isEmpty, jpeg.count <= 8_000_000 else { throw ReaderWallpaperFailure.tooLarge }
        let image = try Self.decodeImage(jpeg)
        let encoded = try JSONEncoder().encode(Envelope(version: 2, jpeg: jpeg, adjustment: adjustment))
        guard encoded.count <= maximumRecordBytes else { throw ReaderWallpaperFailure.tooLarge }
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try encoded.write(to: recordURL, options: .atomic)
        return ReaderWallpaperSnapshot(image: image, adjustment: adjustment, jpeg: jpeg)
    }

    func load() throws -> ReaderWallpaperSnapshot? {
        if FileManager.default.fileExists(atPath: recordURL.path) {
            let encoded = try readBounded(recordURL, limit: maximumRecordBytes)
            let envelope = try JSONDecoder().decode(Envelope.self, from: encoded)
            guard envelope.version == 2 else { throw ReaderWallpaperFailure.unsupportedVersion }
            try envelope.adjustment.validate()
            let image = try Self.decodeImage(envelope.jpeg)
            return ReaderWallpaperSnapshot(image: image, adjustment: envelope.adjustment, jpeg: envelope.jpeg)
        }
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return nil }
        let image = try Self.decodeImage(readBounded(legacyURL, limit: 20_000_000))
        var adjustment = ReaderWallpaperAdjustment()
        adjustment.usesLightText = image.isDarkPerception
        return ReaderWallpaperSnapshot(image: image, adjustment: adjustment)
    }

    func clear() throws {
        for url in [recordURL, legacyURL] where FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static func decodeImage(_ bytes: Data) throws -> UIImage {
        guard !bytes.isEmpty, bytes.count <= 20_000_000 else { throw ReaderWallpaperFailure.tooLarge }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(bytes as CFData, sourceOptions) else { throw ReaderWallpaperFailure.invalidImage }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: ReaderWallpaperLayoutPolicy.maxPixelDimension]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ReaderWallpaperFailure.invalidImage }
        return UIImage(cgImage: image)
    }

    private func readBounded(_ url: URL, limit: Int) throws -> Data {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let bytes = try file.read(upToCount: limit + 1) ?? Data()
        guard bytes.count <= limit else { throw ReaderWallpaperFailure.tooLarge }
        return bytes
    }

    private struct Envelope: Codable {
        let version: Int
        let jpeg: Data
        let adjustment: ReaderWallpaperAdjustment
    }
}
