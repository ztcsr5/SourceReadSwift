import Foundation

/// 本地音频朗读包。
///
/// 朗读引擎多出一条 `.file` 通道：用户在设置里导入一批音频文件，
/// 文件名用「段落序号」命名（`0.mp3`、`12.m4a`，也接受 `p12.mp3`），
/// 朗读到第 N 段就直接播对应文件，不再走合成、也不联网。
///
/// 为什么按段落而不是按章：现有朗读队列本身就是逐段推进
/// （`ReaderSpeechController.speakNext` → `playSegment(index:text:)`），
/// 段落序号是这条链上唯一稳定的键；按章绑定会在换章、跳过段落、
/// 从中间开始朗读时全部错位。
enum LocalVoiceLibrary {
    static let directoryName = "local_voice"

    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "caf", "aif", "aiff", "flac"
    ]

    static func ensureDirectory() {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue {
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    /// 已导入文件（按文件名自然序）。用于设置页展示与计数。
    static func importedFileNames() -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names
            .filter { supportedExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    static var isEmpty: Bool {
        importedFileNames().isEmpty
    }

    /// 导入（复制）用户选中的音频。同名文件会被覆盖，返回成功导入的数量。
    @discardableResult
    static func importFiles(_ urls: [URL]) -> Int {
        ensureDirectory()
        var imported = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.copyItem(at: url, to: destination)
                imported += 1
            } catch {
                continue
            }
        }
        return imported
    }

    /// 段落序号解析：`12.mp3`、`p12.mp3`、`P12.mp3`、`12 - 标题.mp3` 都认。
    static func paragraphIndex(ofFileName name: String) -> Int? {
        let stem = (name as NSString).deletingPathExtension
        var digits = ""
        for character in stem {
            if character.isNumber {
                digits.append(character)
            } else if digits.isEmpty, character == "p" || character == "P" {
                continue
            } else if digits.isEmpty {
                continue
            } else {
                break
            }
        }
        return Int(digits)
    }

    /// 该段落对应的音频文件；没有就返回 nil（调用方负责跳过或回退）。
    static func fileURL(forParagraph index: Int) -> URL? {
        guard index >= 0 else { return nil }
        for name in importedFileNames() where paragraphIndex(ofFileName: name) == index {
            return directory.appendingPathComponent(name)
        }
        return nil
    }

    static var paragraphIndexRange: ClosedRange<Int>? {
        let indices = importedFileNames().compactMap(paragraphIndex(ofFileName:))
        guard let minimum = indices.min(), let maximum = indices.max() else { return nil }
        return minimum...maximum
    }

    static func clear() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for name in names {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        }
    }
}
