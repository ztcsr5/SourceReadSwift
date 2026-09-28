import Foundation
import UIKit
import CoreText
import UniformTypeIdentifiers

public struct CustomFontItem: Identifiable, Hashable, Codable, Sendable {
    public var id: String { fileName }
    public let fileName: String
    public let displayName: String
    public let postScriptName: String
    public let fileSize: Int64
    public let dateAdded: Date

    public var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    public init(
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
public final class CustomFontManager: ObservableObject {
    public static let shared = CustomFontManager()

    @Published public private(set) var installedFonts: [CustomFontItem] = []
    @Published public private(set) var lastErrorMessage: String?

    public let fontsDirectory: URL

    public init(fileManager: FileManager = .default) {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let dir = appSupport
            .appendingPathComponent("SourceReadSwift", isDirectory: true)
            .appendingPathComponent("Fonts", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fontsDirectory = dir
        reloadAndRegisterFonts()
    }

    public func reloadAndRegisterFonts() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: fontsDirectory, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]) else {
            installedFonts = []
            return
        }

        var items: [CustomFontItem] = []
        let allowedExtensions: Set<String> = ["ttf", "otf", "ttc", "woff"]

        for fileURL in files {
            let ext = fileURL.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }
            if let item = registerFont(at: fileURL) {
                items.append(item)
            }
        }

        installedFonts = items.sorted { $0.dateAdded > $1.dateAdded }
    }

    @discardableResult
    public func registerFont(at url: URL) -> CustomFontItem? {
        var error: Unmanaged<CFError>?
        // CTFontManagerRegisterFontsForURL returns true on fresh register, or false if already registered.
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)

        guard let provider = CGDataProvider(url: url as CFURL),
              let cgFont = CGFont(provider) else {
            return nil
        }

        let psName = (cgFont.postScriptName as String?) ?? url.deletingPathExtension().lastPathComponent
        let fullName = (cgFont.fullName as String?) ?? psName
        let attr = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attr[.size] as? NSNumber)?.int64Value ?? 0
        let date = (attr[.creationDate] as? Date) ?? Date()

        return CustomFontItem(
            fileName: url.lastPathComponent,
            displayName: fullName,
            postScriptName: psName,
            fileSize: size,
            dateAdded: date
        )
    }

    public func importFont(from sourceURL: URL) throws -> CustomFontItem {
        let shouldStop = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if shouldStop {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileName = sourceURL.lastPathComponent
        let destinationURL = fontsDirectory.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            var error: Unmanaged<CFError>?
            CTFontManagerUnregisterFontsForURL(destinationURL as CFURL, .process, &error)
            try? FileManager.default.removeItem(at: destinationURL)
        }

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

    public func deleteFont(_ item: CustomFontItem) {
        let fileURL = fontsDirectory.appendingPathComponent(item.fileName)
        var error: Unmanaged<CFError>?
        CTFontManagerUnregisterFontsForURL(fileURL as CFURL, .process, &error)
        try? FileManager.default.removeItem(at: fileURL)
        reloadAndRegisterFonts()
    }

    public func uiFont(postScriptName: String, size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont? {
        if let font = UIFont(name: postScriptName, size: size) {
            return font
        }
        return nil
    }
}
