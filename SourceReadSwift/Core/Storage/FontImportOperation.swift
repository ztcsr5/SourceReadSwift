import CoreText
import Foundation

/// Coordinates file-provider access and font IO away from the UI actor.
enum FontImportOperation {
    static func prepare(source: URL, directory: URL, installed: [CustomFontItem]) throws -> CustomFontItem {
        precondition(!Thread.isMainThread, "Font file access must not block the picker dismissal")
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var outcome: Result<CustomFontItem, Error>?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
            outcome = Result { try copyFont(source: readable, directory: directory, installed: installed) }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw CocoaError(.fileReadUnknown) }
        return try outcome.get()
    }

    private static func copyFont(source: URL, directory: URL, installed: [CustomFontItem]) throws -> CustomFontItem {
        let properties = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        try FontImportPolicy.validate(suffix: source.pathExtension, bytes: properties.fileSize ?? 0)
        guard properties.isRegularFile == true,
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(source as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            throw NSError(domain: "FontImport", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "无法读取字体内容，请下载完整文件后重试。"])
        }
        let face = CTFontCreateWithFontDescriptor(descriptor, 16, nil)
        let name = CTFontCopyPostScriptName(face) as String
        if let existing = installed.first(where: { $0.postScriptName == name }) { return existing }
        let destination = directory.appendingPathComponent(UUID().uuidString + "." + source.pathExtension.lowercased())
        try FileManager.default.copyItem(at: source, to: destination)
        // Only this new UUID-owned candidate may be removed on failure.
        var shouldKeep = false
        defer { if !shouldKeep { try? FileManager.default.removeItem(at: destination) } }
        var registrationError: Unmanaged<CFError>?
        let didRegister = CTFontManagerRegisterFontsForURL(destination as CFURL, .process, &registrationError)
        let failure = registrationError?.takeRetainedValue()
        if !didRegister, failure.map({ CFErrorGetCode($0) }) != Int(CTFontManagerError.alreadyRegistered.rawValue) {
            if let failure { throw failure as Error }
            throw NSError(domain: "FontImport", code: 4,
                userInfo: [NSLocalizedDescriptionKey: "系统未能注册此字体，请尝试另一份 TTF 或 OTF 文件。"])
        }
        shouldKeep = true
        return CustomFontItem(fileName: destination.lastPathComponent,
            displayName: CTFontCopyFullName(face) as String, postScriptName: name,
            fileSize: Int64(properties.fileSize ?? 0))
    }
}
