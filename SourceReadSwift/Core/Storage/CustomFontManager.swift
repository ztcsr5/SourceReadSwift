import Foundation
import UIKit
import CoreText
import UniformTypeIdentifiers

struct CustomFontItem: Identifiable, Hashable, Codable, Sendable {
    var id: String { fileName }
    let fileName: String
    let displayName: String
    let postScriptName: String
    let fileSize: Int64
    let dateAdded: Date

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    init(
        fileName: String,
        displayName: String,
        postScriptName: String,
        fileSize: Int64,
        dateAdded: Date = Date()
    ) {
        self.fileName = fileName
        self.displayName = displayName
        self.postScriptName = postScriptName
        self.fileSize = fileSize
        self.dateAdded = dateAdded
    }
}

@MainActor
final class CustomFontManager: ObservableObject {
    static let shared = CustomFontManager(deferInitialLoad: true)

    @Published private(set) var installedFonts: [CustomFontItem] = []
    @Published private(set) var lastErrorMessage: String?

    let fontsDirectory: URL

    init(fileManager: FileManager = .default, rootURL: URL? = nil, deferInitialLoad: Bool = false) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = rootURL ?? appSupport
            .appendingPathComponent("SourceReadSwift", isDirectory: true)
            .appendingPathComponent("Fonts", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fontsDirectory = dir
        if deferInitialLoad {
            Task { @MainActor [weak self] in
                await self?.reloadAndRegisterFontsAsync()
            }
        } else {
            reloadAndRegisterFonts()
        }
    }

    func reloadAndRegisterFontsAsync() async {
        let dir = fontsDirectory
        let items = await Task.detached(priority: .utility) {
            Self.scanAndRegisterFonts(in: dir)
        }.value
        installedFonts = items
    }

    func reloadAndRegisterFonts() {
        installedFonts = Self.scanAndRegisterFonts(in: fontsDirectory)
    }

    private nonisolated static func scanAndRegisterFonts(in directory: URL) -> [CustomFontItem] {
        defer { CustomFontLocations.markInitialScanCompleted() }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
        ) else {
            return []
        }

        var items: [CustomFontItem] = []
        let allowedExtensions = FontImportPolicy.extensions

        for fileURL in files {
            let ext = fileURL.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }
            if let item = registerFontDescriptor(at: fileURL) {
                items.append(item)
            }
        }

        return items.sorted { $0.dateAdded > $1.dateAdded }
    }

    @discardableResult
    func registerFont(at url: URL) -> CustomFontItem? {
        Self.registerFontDescriptor(at: url)
    }

    private nonisolated static func registerFontDescriptor(at url: URL) -> CustomFontItem? {
        var error: Unmanaged<CFError>?
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)

        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            return nil
        }

        let face = CTFontCreateWithFontDescriptor(descriptor, 16, nil)
        let psName = CTFontCopyPostScriptName(face) as String
        let fullName = CTFontCopyFullName(face) as String
        let attr = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attr[.size] as? NSNumber)?.int64Value ?? 0
        let date = (attr[.creationDate] as? Date) ?? Date()
        CustomFontLocations.register(postScriptName: psName, file: url)

        return CustomFontItem(
            fileName: url.lastPathComponent,
            displayName: fullName,
            postScriptName: psName,
            fileSize: size,
            dateAdded: date
        )
    }

    func importFont(from sourceURL: URL) throws -> CustomFontItem {
        let shouldStop = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStop {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = sourceURL.lastPathComponent
        let properties = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        try FontImportPolicy.validate(suffix: sourceURL.pathExtension, bytes: properties.fileSize ?? 0)
        guard properties.isRegularFile == true,
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(sourceURL as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            throw NSError(domain: "FontImport", code: 3, userInfo: [NSLocalizedDescriptionKey: "文件不是可读取的字体，请先下载完整文件或重新导出。"])
        }
        let postScriptName = CTFontCopyPostScriptName(CTFontCreateWithFontDescriptor(descriptor, 16, nil)) as String
        if let existing = installedFonts.first(where: { $0.postScriptName == postScriptName }) { return existing }
        // A failed import must never destroy a previously usable font with the same filename.
        let destinationURL = fontsDirectory.appendingPathComponent(UUID().uuidString + "-" + fileName)

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        guard let item = registerFont(at: destinationURL) else {
            try? FileManager.default.removeItem(at: destinationURL)
            let err = NSError(
                domain: "CustomFontManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "无法解析字体文件或字体格式不受支持"]
            )
            lastErrorMessage = err.localizedDescription
            throw err
        }

        reloadAndRegisterFonts()
        lastErrorMessage = nil
        return item
    }

    /// The picker path keeps provider coordination, copying and CoreText parsing off main.
    func importPickedFont(from sourceURL: URL) async throws -> CustomFontItem {
        let directory = fontsDirectory
        let installed = installedFonts
        do {
            let item = try await FontImportRequest.perform(operation: { cancellation in
                try FontImportOperation.preparePickedCopy(source: sourceURL, directory: directory, installed: installed, cancellation: cancellation)
            }, discard: { FontImportOperation.discardCandidate($0, directory: directory, installed: installed) })
            if Task.isCancelled {
                FontImportOperation.discardCandidate(item, directory: directory, installed: installed)
                throw CancellationError()
            }
            if !installedFonts.contains(where: { $0.postScriptName == item.postScriptName }) {
                installedFonts.insert(item, at: 0)
            }
            CustomFontLocations.register(postScriptName: item.postScriptName,
                file: fontsDirectory.appendingPathComponent(item.fileName))
            lastErrorMessage = nil
            return item
        } catch {
            lastErrorMessage = error.localizedDescription
            throw error
        }
    }

    func deleteFont(_ item: CustomFontItem) {
        CustomFontLocations.remove(item.postScriptName)
        let fileURL = fontsDirectory.appendingPathComponent(item.fileName)
        var error: Unmanaged<CFError>?
        CTFontManagerUnregisterFontsForURL(fileURL as CFURL, .process, &error)
        try? FileManager.default.removeItem(at: fileURL)
        reloadAndRegisterFonts()
    }

    func uiFont(postScriptName: String, size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont? {
        if let font = UIFont(name: postScriptName, size: size) {
            return font
        }
        return nil
    }
}
