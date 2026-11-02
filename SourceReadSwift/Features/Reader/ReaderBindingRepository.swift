import Foundation
import Combine
import UIKit

struct ReaderBindingRecord: Identifiable, Codable, Equatable, Sendable {
    let version: Int
    let id: UUID
    let title: String
    let createdAt: Date
    let preferences: ReaderBindingPreferences
    let hasWallpaper: Bool
    func validate() throws {
        guard version == 1, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 32 else {
            throw NSError(domain: "ReaderBinding", code: 2, userInfo: [NSLocalizedDescriptionKey: "装帧方案名称需为 1–32 个字，且版本受支持。"])
        }
        try preferences.validate()
        guard hasWallpaper == (preferences.text("reader.background") == "custom") else {
            throw NSError(domain: "ReaderBinding", code: 3, userInfo: [NSLocalizedDescriptionKey: "装帧方案缺少对应的自定义壁纸，未应用。"])
        }
    }
}

struct ReaderBindingWallpaper: Codable, Sendable {
    let jpeg: Data
    let adjustment: ReaderWallpaperAdjustment
}

/// Serial, bounded, atomic per-record writes. Wallpaper is committed before its record becomes visible.
actor ReaderBindingRepository {
    let root: URL
    init(root: URL) { self.root = root }
    func records() throws -> [ReaderBindingRecord] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasSuffix(".wallpaper.json") }
        guard files.count <= 50 else { throw CocoaError(.fileReadTooLarge) }
        return try files.map { url in
            let record = try JSONDecoder().decode(ReaderBindingRecord.self, from: read(url, limit: 64 * 1024))
            try record.validate()
            guard url.deletingPathExtension().lastPathComponent == record.id.uuidString else { throw CocoaError(.fileReadCorruptFile) }
            return record
        }.sorted { $0.createdAt > $1.createdAt }
    }
    func save(_ record: ReaderBindingRecord, wallpaper: ReaderBindingWallpaper?) throws {
        try record.validate()
        guard (wallpaper != nil) == record.hasWallpaper, try records().count < 50 else { throw CocoaError(.fileWriteOutOfSpace) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let path = recordURL(record.id), asset = wallpaperURL(record.id)
        guard !FileManager.default.fileExists(atPath: path.path) else { throw CocoaError(.fileWriteFileExists) }
        do {
            if let wallpaper {
                try wallpaper.adjustment.validate()
                guard !wallpaper.jpeg.isEmpty, wallpaper.jpeg.count <= 8_000_000 else { throw ReaderWallpaperFailure.tooLarge }
                _ = try ReaderWallpaperRepository.decodeImage(wallpaper.jpeg)
                try JSONEncoder().encode(wallpaper).write(to: asset, options: .atomic)
            }
            try JSONEncoder().encode(record).write(to: path, options: .atomic)
        } catch {
            if wallpaper != nil { try? FileManager.default.removeItem(at: asset) }
            throw error
        }
    }
    func wallpaper(for id: UUID) throws -> ReaderBindingWallpaper {
        let wallpaper = try JSONDecoder().decode(ReaderBindingWallpaper.self, from: read(wallpaperURL(id), limit: 12_000_000))
        try wallpaper.adjustment.validate()
        guard wallpaper.jpeg.count <= 8_000_000 else { throw ReaderWallpaperFailure.tooLarge }
        return wallpaper
    }
    func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: recordURL(id))
        let asset = wallpaperURL(id)
        if FileManager.default.fileExists(atPath: asset.path) { try FileManager.default.removeItem(at: asset) }
    }
    private func recordURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".json") }
    private func wallpaperURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".wallpaper.json") }
    private func read(_ url: URL, limit: Int) throws -> Data {
        guard url.resolvingSymlinksInPath().deletingLastPathComponent().standardizedFileURL.path == root.resolvingSymlinksInPath().standardizedFileURL.path else { throw CocoaError(.fileReadNoPermission) }
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        let bytes = try file.read(upToCount: limit + 1) ?? Data()
        guard bytes.count <= limit else { throw CocoaError(.fileReadTooLarge) }
        return bytes
    }
}

@MainActor final class ReaderBindingStore: ObservableObject {
    @Published private(set) var records: [ReaderBindingRecord] = []
    private let repository: ReaderBindingRepository
    init(root: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        repository = ReaderBindingRepository(root: root ?? support.appendingPathComponent("SourceReadSwift/ReaderBindings", isDirectory: true))
    }
    func reload() async throws { records = try await repository.records() }
    func save(title: String, defaults: UserDefaults = .standard) async throws {
        await ReaderCustomWallpaperStore.warmWallpaper()
        let preferences = try ReaderBindingPreferences.capture(defaults)
        let usesWallpaper = preferences.text("reader.background") == "custom"
        var wallpaper: ReaderBindingWallpaper?
        if usesWallpaper {
            guard let image = ReaderCustomWallpaperStore.cachedWallpaper else { throw ReaderWallpaperFailure.invalidImage }
            let adjustment = ReaderCustomWallpaperStore.adjustment
            let bytes: Data?
            if let cached = ReaderCustomWallpaperStore.cachedJPEG { bytes = cached }
            else { bytes = await Task.detached(priority: .userInitiated) { image.jpegData(compressionQuality: 0.85) }.value }
            guard let bytes else { throw ReaderWallpaperFailure.invalidImage }
            wallpaper = ReaderBindingWallpaper(jpeg: bytes, adjustment: adjustment)
        }
        let record = ReaderBindingRecord(version: 1, id: UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: Date(), preferences: preferences, hasWallpaper: usesWallpaper)
        try await repository.save(record, wallpaper: wallpaper); try await reload()
    }
    func apply(_ record: ReaderBindingRecord, defaults: UserDefaults = .standard) async throws {
        try record.validate()
        let preferences = record.preferences
        if preferences.text("reader.fontFamily") == ReaderFontFamily.custom.rawValue || preferences.text("reader.chapterTitleFamily") == ReaderFontFamily.custom.rawValue {
            let name = preferences.text("reader.customFontPostScriptName")
            guard let file = CustomFontLocations.file(for: name), FileManager.default.fileExists(atPath: file.path) else {
                throw NSError(domain: "ReaderBinding", code: 4, userInfo: [NSLocalizedDescriptionKey: "此方案使用的自定义字体尚未安装，请先导入原字体；原设置未改变。"])
            }
        }
        if record.hasWallpaper {
            let wallpaper = try await repository.wallpaper(for: record.id)
            try await ReaderCustomWallpaperStore.restoreEncodedWallpaper(wallpaper.jpeg, adjustment: wallpaper.adjustment)
        }
        try preferences.apply(to: defaults)
        defaults.set(UUID().uuidString, forKey: "reader.bindingRevision")
    }
    func delete(_ id: UUID) async throws { try await repository.delete(id); try await reload() }
}
