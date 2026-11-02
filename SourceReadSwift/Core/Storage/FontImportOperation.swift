import CoreText
import Foundation

/// Coordinates file-provider access and font IO away from the UI actor.
enum FontImportOperation {
    static func prepare(source: URL, directory: URL, installed: [CustomFontItem], cancellation: FontImportCancellation = .init()) throws -> CustomFontItem {
        precondition(!Thread.isMainThread, "Font file access must not block the picker dismissal")
        try cancellation.check()
        guard source.isFileURL else { throw CocoaError(.fileReadUnsupportedScheme) }
        // asCopy document pickers already provide a sandbox copy. Coordinating
        // that copy again can wait for a provider that no longer owns the file.
        if !requiresCoordination(source: source) {
            return try copyFont(source: source, directory: directory, installed: installed, cancellation: cancellation)
        }
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var outcome: Result<CustomFontItem, Error>?
        let coordinator = NSFileCoordinator()
        try cancellation.coordinate(coordinator)
        coordinator.coordinate(readingItemAt: source, options: [], error: &coordinationError) { readable in
            outcome = Result { try copyFont(source: readable, directory: directory, installed: installed, cancellation: cancellation) }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw CocoaError(.fileReadUnknown) }
        return try outcome.get()
    }

    static func requiresCoordination(source: URL, sandbox: URL = URL(fileURLWithPath: NSHomeDirectory())) -> Bool {
        let root = sandbox.resolvingSymlinksInPath().standardizedFileURL.path
        let path = source.resolvingSymlinksInPath().standardizedFileURL.path
        return !source.isFileURL || !path.hasPrefix(root + "/")
    }

    static func discardCandidate(_ item: CustomFontItem, directory: URL, installed: [CustomFontItem]) {
        guard !installed.contains(where: { $0.fileName == item.fileName }),
              UUID(uuidString: URL(fileURLWithPath: item.fileName).deletingPathExtension().lastPathComponent) != nil,
              !item.fileName.contains("/") else { return }
        let file = directory.appendingPathComponent(item.fileName)
        CTFontManagerUnregisterFontsForURL(file as CFURL, .process, nil)
        try? FileManager.default.removeItem(at: file)
    }

    private static func copyFont(source: URL, directory: URL, installed: [CustomFontItem], cancellation: FontImportCancellation) throws -> CustomFontItem {
        try cancellation.check()
        let properties = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        try FontImportPolicy.validate(suffix: source.pathExtension, bytes: properties.fileSize ?? 0)
        guard properties.isRegularFile == true else { throw CocoaError(.fileReadUnsupportedScheme) }
        let destination = directory.appendingPathComponent(UUID().uuidString + "." + source.pathExtension.lowercased())
        try FileManager.default.copyItem(at: source, to: destination)
        var shouldKeep = false
        defer { if !shouldKeep { try? FileManager.default.removeItem(at: destination) } }
        try cancellation.check()
        let copied = try destination.resourceValues(forKeys: [.fileSizeKey])
        try FontImportPolicy.validate(suffix: destination.pathExtension, bytes: copied.fileSize ?? 0)
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(destination as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first else {
            throw NSError(domain: "FontImport", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "无法读取字体内容，请下载完整文件后重试。"])
        }
        let face = CTFontCreateWithFontDescriptor(descriptor, 16, nil)
        let name = CTFontCopyPostScriptName(face) as String
        if let existing = installed.first(where: { $0.postScriptName == name }) { return existing }
        try cancellation.check()
        var registrationError: Unmanaged<CFError>?
        let didRegister = CTFontManagerRegisterFontsForURL(destination as CFURL, .process, &registrationError)
        let failure = registrationError?.takeRetainedValue()
        if !didRegister {
            let code = failure.map { CFErrorGetCode($0) }
            let isKnownCollision = code == Int(CTFontManagerError.alreadyRegistered.rawValue)
                || code == Int(CTFontManagerError.duplicatedName.rawValue)
            // Bundled/system faces may already own this exact PostScript name.
            // Accept only a real resolvable face, never a silent fallback font.
            let available = CTFontCreateWithName(name as CFString, 16, nil)
            if !isKnownCollision || CTFontCopyPostScriptName(available) as String != name {
                if let failure { throw failure as Error }
                throw NSError(domain: "FontImport", code: 4,
                    userInfo: [NSLocalizedDescriptionKey: "系统未能注册此字体，请尝试另一份 TTF 或 OTF 文件。"])
            }
        }
        do { try cancellation.check() }
        catch {
            if didRegister { CTFontManagerUnregisterFontsForURL(destination as CFURL, .process, nil) }
            throw error
        }
        shouldKeep = true
        return CustomFontItem(fileName: destination.lastPathComponent,
            displayName: CTFontCopyFullName(face) as String, postScriptName: name,
            fileSize: Int64(properties.fileSize ?? 0))
    }
}
