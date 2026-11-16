import Foundation

enum SourceExportError: LocalizedError, Equatable {
    case emptySources
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .emptySources:
            return "没有可导出的书源"
        case .encodingFailed:
            return "书源 JSON 编码失败"
        }
    }
}

/// Shared selection/batch-toolbar reconciliation for SourceManager lists so deleting
/// the last item never leaves an orphaned batch toolbar on top of the empty state.
enum SourceSelectionStateHelper {
    static func shouldShowBatchToolbar(isManaging: Bool, totalCount: Int) -> Bool {
        isManaging && totalCount > 0
    }

    static func reconciledManagingState(_ isManaging: Bool, totalCount: Int) -> Bool {
        totalCount > 0 ? isManaging : false
    }

    static func reconciledSelection(_ selectedIDs: Set<String>, validIDs: Set<String>) -> Set<String> {
        guard !validIDs.isEmpty else { return [] }
        return selectedIDs.intersection(validIDs)
    }
}

/// Legado-compatible JSON exporter for `BookSource` arrays and single-source backups.
enum SourceBookExportSupport {
    private static let managedTopLevelKeys: Set<String> = [
        "bookSourceName",
        "bookSourceUrl",
        "bookSourceGroup",
        "bookSourceType",
        "enabled",
        "weight",
        "searchUrl",
        "exploreUrl",
        "ruleSearch",
        "ruleBookInfo",
        "ruleToc",
        "ruleContent",
        "ruleExplore",
        "header",
        "loginUrl",
        "loginCheckJs",
        "loginUi",
        "customConfig",
        "raw",
        // Legacy alias keys superseded by the authoritative properties above
        "sourceName",
        "name",
        "sourceUrl",
        "url",
        "sourceGroup",
        "group",
        "sourceType",
        "enable",
        "headers",
        "bookSourceHeader"
    ]

    private static let legadoBoolKeys: Set<String> = [
        "enabledExplore",
        "enabledCookieJar",
        "enabledReview",
        "eventListener",
        "customButton"
    ]

    private static let legadoIntKeys: Set<String> = [
        "customOrder",
        "lastUpdateTime",
        "respondTime",
        "serialNumber"
    ]

    /// Encodes `sources` as a pretty-printed Legado-compatible UTF-8 JSON array (`[...]`).
    static func jsonData(for sources: [BookSource]) throws -> Data {
        guard !sources.isEmpty else {
            throw SourceExportError.emptySources
        }
        let records = sources.map(LegadoExportSourceRecord.init(source:))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(records)
    }

    /// Encodes `sources` as a Legado-compatible UTF-8 JSON string (`[...]`).
    static func jsonString(for sources: [BookSource]) throws -> String {
        let data = try jsonData(for: sources)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SourceExportError.encodingFailed
        }
        return text
    }

    /// Returns a filesystem-safe `.json` filename describing the exported subset.
    static func suggestedFileName(
        for sources: [BookSource],
        label: String? = nil,
        date: Date = Date()
    ) -> String {
        if sources.count == 1, let only = sources.first {
            let safeName = sanitizeFileComponent(only.bookSourceName)
            let stem = safeName.isEmpty ? "book_source" : safeName
            return "\(stem).json"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: date)

        let cleanLabel = label.map(sanitizeFileComponent).flatMap { $0.isEmpty ? nil : $0 }
        if let cleanLabel {
            return "书源导出_\(cleanLabel)_\(sources.count)个_\(timestamp).json"
        }
        return "书源导出_\(sources.count)个_\(timestamp).json"
    }

    /// Writes `sources` to a temporary UTF-8 `.json` file ready for `UIActivityViewController`.
    static func writeTemporaryJSONFile(
        for sources: [BookSource],
        label: String? = nil,
        directory: URL = FileManager.default.temporaryDirectory,
        date: Date = Date()
    ) throws -> URL {
        let data = try jsonData(for: sources)
        let exportFolder = directory.appendingPathComponent("SourceExport-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        let fileURL = exportFolder.appendingPathComponent(suggestedFileName(for: sources, label: label, date: date))
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    static func sanitizeFileComponent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\r\n\t")
        let parts = trimmed.components(separatedBy: forbidden)
        guard parts.contains(where: { !$0.isEmpty }) else { return "" }
        let joined = parts.joined(separator: "_")
        if joined.count <= 48 {
            return joined
        }
        return String(joined.prefix(48))
    }

    private struct ExportCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }

        init(_ value: String) {
            self.stringValue = value
        }
    }

    private struct LegadoExportSourceRecord: Encodable {
        let source: BookSource

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: ExportCodingKey.self)

            // Lift preserved extra Legado keys from `source.raw` to the top level
            // so both Android Legado and SourceReadSwift restore them losslessly.
            for key in source.raw.keys.sorted() {
                guard !managedTopLevelKeys.contains(key),
                      let value = source.raw[key],
                      !value.isEmpty else {
                    continue
                }
                let codingKey = ExportCodingKey(key)
                if legadoBoolKeys.contains(key) {
                    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if normalized == "true" || normalized == "1" {
                        try container.encode(true, forKey: codingKey)
                        continue
                    } else if normalized == "false" || normalized == "0" {
                        try container.encode(false, forKey: codingKey)
                        continue
                    }
                }
                if legadoIntKeys.contains(key),
                   let intVal = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    try container.encode(intVal, forKey: codingKey)
                    continue
                }
                try container.encode(value, forKey: codingKey)
            }

            try container.encode(source.bookSourceName, forKey: ExportCodingKey("bookSourceName"))
            try container.encode(source.bookSourceUrl, forKey: ExportCodingKey("bookSourceUrl"))
            try container.encodeIfPresent(source.bookSourceGroup, forKey: ExportCodingKey("bookSourceGroup"))
            try container.encode(source.bookSourceType, forKey: ExportCodingKey("bookSourceType"))
            try container.encode(source.enabled, forKey: ExportCodingKey("enabled"))
            try container.encode(source.weight, forKey: ExportCodingKey("weight"))
            try container.encodeIfPresent(source.searchUrl, forKey: ExportCodingKey("searchUrl"))
            try container.encodeIfPresent(source.exploreUrl, forKey: ExportCodingKey("exploreUrl"))
            try container.encodeIfPresent(source.ruleSearch, forKey: ExportCodingKey("ruleSearch"))
            try container.encodeIfPresent(source.ruleBookInfo, forKey: ExportCodingKey("ruleBookInfo"))
            try container.encodeIfPresent(source.ruleToc, forKey: ExportCodingKey("ruleToc"))
            try container.encodeIfPresent(source.ruleContent, forKey: ExportCodingKey("ruleContent"))
            try container.encodeIfPresent(source.ruleExplore, forKey: ExportCodingKey("ruleExplore"))
            try container.encodeIfPresent(source.header, forKey: ExportCodingKey("header"))
            try container.encodeIfPresent(source.loginUrl, forKey: ExportCodingKey("loginUrl"))
            try container.encodeIfPresent(source.loginCheckJs, forKey: ExportCodingKey("loginCheckJs"))
            try container.encodeIfPresent(source.loginUi, forKey: ExportCodingKey("loginUi"))
            try container.encodeIfPresent(source.customConfig, forKey: ExportCodingKey("customConfig"))
        }
    }
}
