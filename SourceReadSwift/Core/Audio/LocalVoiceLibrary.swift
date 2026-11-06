import Foundation

struct LocalVoiceImportReport: Sendable {
    var importedCount = 0
    var skippedCount = 0
    var failures: [String] = []
}

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
    private static let fileLock = NSLock()

    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(directoryName, isDirectory: true)
    }

    private static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "caf", "aif", "aiff", "flac"
    ]

    static func ensureDirectory() {
        do { try prepareDirectory() }
        catch { NSLog("Local audio directory is unavailable: %@", String(describing: type(of: error))) }
    }

    private static func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
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
        importFilesWithReport(urls).importedCount
    }

    /// Copies complete files atomically; a failed replacement preserves the previous audio.
    static func importFilesWithReport(_ urls: [URL]) -> LocalVoiceImportReport {
        fileLock.lock(); defer { fileLock.unlock() }
        var report = LocalVoiceImportReport()
        do { try prepareDirectory() }
        catch {
            report.failures.append("无法创建音频目录：\(error.localizedDescription)")
            return report
        }
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { report.skippedCount += 1; continue }
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            do {
                let properties = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard properties.isRegularFile == true, (properties.fileSize ?? 0) > 0 else {
                    throw NSError(domain: "LocalVoiceImport", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "请选择已下载完成的非空音频文件。"])
                }
                if url.standardizedFileURL.resolvingSymlinksInPath() != destination.standardizedFileURL.resolvingSymlinksInPath() {
                    let audio = try Data(contentsOf: url, options: .mappedIfSafe)
                    try audio.write(to: destination, options: .atomic)
                }
                report.importedCount += 1
            } catch {
                report.failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        return report
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
        let failures = clearReportingFailures()
        if !failures.isEmpty { NSLog("Could not remove %ld local audio files", failures.count) }
    }

    /// Returns the files that could not be removed so the settings screen can show partial failure.
    static func clearReportingFailures() -> [String] {
        fileLock.lock(); defer { fileLock.unlock() }
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let names: [String]
        do { names = try FileManager.default.contentsOfDirectory(atPath: directory.path) }
        catch { return ["无法读取音频目录：\(error.localizedDescription)"] }
        var failures: [String] = []
        for name in names {
            do { try FileManager.default.removeItem(at: directory.appendingPathComponent(name)) }
            catch { failures.append("\(name)：\(error.localizedDescription)") }
        }
        return failures
    }
}
