import CryptoKit
import Foundation
import UIKit
import XCTest
@testable import SourceReadSwift

/// Opt in with PRIVATE_SOURCE_CORPUS_DIR and PRIVATE_SOURCE_CORPUS_OUTPUT outside the checkout.
/// MODE=inspect reads all records without running scripts or HTTP. MODE=live also requires FILE,
/// with START=0 and LIMIT=25 (maximum 100); KEYWORD defaults to 剑来. Never attach private reports.
final class PrivateSourceCorpusProbeTests: XCTestCase {
    func testExternalPrivateCorpus() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["PRIVATE_SOURCE_CORPUS_DIR"], !directory.isEmpty else {
            throw XCTSkip("PRIVATE_CORPUS external input was not supplied")
        }
        do {
            let selection = try PrivateCorpusSelection(environment: environment)
            let bundle = try PrivateCorpusInput.load(directory: URL(fileURLWithPath: directory))
            let output = try bundle.outputURL(environment["PRIVATE_SOURCE_CORPUS_OUTPUT"])
            let positions = try selection.positions(in: bundle.entries)
            var report = PrivateCorpusReport(mode: selection.mode, selectedRecords: positions.count,
                rows: bundle.entries.map(\.row))
            try report.write(to: output)
            if selection.mode == "inspect" {
                for position in positions {
                    report.rows[position] = PrivateCorpusRunner.inspect(bundle.entries[position])
                }
                try report.write(to: output)
            } else {
                try await withThrowingTaskGroup(of: (Int, PrivateCorpusRow).self) { group in
                    var pending = positions.makeIterator()
                    for _ in 0..<min(3, positions.count) {
                        if let position = pending.next() {
                            let entry = bundle.entries[position]
                            group.addTask { (position, await PrivateCorpusRunner.probe(entry, keyword: selection.keyword)) }
                        }
                    }
                    while true {
                        guard let completed = try await group.next() else { break }
                        let (position, row) = completed
                        report.rows[position] = row
                        try report.write(to: output)
                        print("PRIVATE_CORPUS row=\(row.fileId):\(row.index) completed=1")
                        if let next = pending.next() {
                            let entry = bundle.entries[next]
                            group.addTask { (next, await PrivateCorpusRunner.probe(entry, keyword: selection.keyword)) }
                        }
                    }
                }
            }
            let completed = report.rows.filter { $0.status != "notRun" }.count
            let stageCounts = Dictionary(grouping: report.rows.flatMap(\.stages), by: \.stage).mapValues(\.count)
            print("PRIVATE_CORPUS records=\(report.rows.count) completed=\(completed) notRun=\(report.rows.count - completed)")
            for stage in stageCounts.keys.sorted() { print("PRIVATE_CORPUS stage=\(stage) count=\(stageCounts[stage] ?? 0)") }
        } catch {
            // XCTest's default error rendering can include private filenames, URLs or source definitions.
            XCTFail("PRIVATE_CORPUS input, selection or external report I/O failed; no private content is printed")
        }
    }

    func testSyntheticFiveFileCorpusRetainsAll1128IdentitiesIncludingDuplicateURLsAndInvalidRows() throws {
        let directory = try makeFixture(counts: [400, 200, 200, 200, 128], invalidLastRow: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = try PrivateCorpusInput.load(directory: directory)
        XCTAssertEqual(bundle.entries.count, 1128)
        XCTAssertEqual(Set(bundle.entries.map { "\($0.row.fileId)|\($0.row.fileSHA)|\($0.row.index)" }).count, 1128)
        XCTAssertEqual(bundle.entries.filter { $0.source != nil }.count, 1127)
        XCTAssertEqual(Set(bundle.entries.compactMap { $0.source?.bookSourceUrl }).count, 1)
        XCTAssertTrue(bundle.entries.allSatisfy { $0.row.status == "notRun" })
        XCTAssertEqual(bundle.entries.last?.row.decodeFailure, "record-decode-failed")
    }

    func testLiveSliceLeavesEveryUnselectedRecordExplicitlyNotRun() throws {
        let directory = try makeFixture(counts: [3, 3, 3, 3, 3])
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundle = try PrivateCorpusInput.load(directory: directory)
        let selection = try PrivateCorpusSelection(environment: ["PRIVATE_SOURCE_CORPUS_MODE": "live",
            "PRIVATE_SOURCE_CORPUS_FILE": "sources-03", "PRIVATE_SOURCE_CORPUS_START": "1", "PRIVATE_SOURCE_CORPUS_LIMIT": "1"])
        let positions = try selection.positions(in: bundle.entries)
        XCTAssertEqual(positions, [7])
        var report = PrivateCorpusReport(mode: "live", selectedRecords: positions.count, rows: bundle.entries.map(\.row))
        report.rows[7] = PrivateCorpusRunner.inspect(bundle.entries[7])
        XCTAssertEqual(report.rows.count, 15)
        XCTAssertEqual(report.rows.filter { $0.status == "notRun" }.count, 14)
        XCTAssertEqual(report.rows[7].fileId, "sources-03")
        XCTAssertEqual(report.rows[7].index, 1)
        XCTAssertFalse(report.rows[7].playbackVerified)
        let encoded = try JSONEncoder().encode(report)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(envelope["totalRecords"] as? Int, 15)
        XCTAssertEqual((envelope["rows"] as? [[String: Any]])?.count, 15)
    }

    func testInspectScansRuleChainAndBuildsStaticRequestWithoutExecutingJavaScript() throws {
        let source = BookSource(bookSourceName: "Synthetic", bookSourceUrl: "https://private-probe.invalid",
            searchUrl: "/search?q={{key}}&p={{page}}",
            ruleSearch: .init(fields: ["bookList": "li", "name": "a@text##^作品##",
                "bookUrl": "@js:while(true){}"]),
            header: "@js:throw new Error('Inspect must not execute header scripts')",
            customConfig: #"{"headers":"@js:throw new Error('Inspect must not execute request options')"}"#,
            raw: ["jsLib": "throw new Error('This script must never execute in inspect mode')"])
        let entry = PrivateCorpusEntry(row: .init(fileId: "sources-01", fileSHA: String(repeating: "a", count: 64), index: 0), source: source)
        let inspected = PrivateCorpusRunner.inspect(entry)
        XCTAssertEqual(inspected.status, "inspected")
        XCTAssertEqual(inspected.coverage, "offline-structure-only")
        XCTAssertTrue(inspected.stages.contains { $0.stage == "search-request" && $0.status == "constructed" })
        XCTAssertTrue(inspected.stages.contains { $0.stage == "search-rules" && $0.deferredCount == 1 })
        XCTAssertFalse(inspected.playbackVerified)
        XCTAssertFalse(inspected.loginPersistenceVerified)
    }

    func testCorruptInputAndEscapingPathsAreRejectedBeforeSourceExecution() throws {
        let directory = try makeFixture(counts: [1, 1, 1, 1, 1])
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("sources-01.json")
        try Data("[]".utf8).write(to: first)
        XCTAssertThrowsError(try PrivateCorpusInput.load(directory: directory))
        XCTAssertThrowsError(try PrivateCorpusInput.confinedURL("../outside.json", in: directory))
        XCTAssertThrowsError(try PrivateCorpusSelection(environment: ["PRIVATE_SOURCE_CORPUS_MODE": "live"]))
        XCTAssertThrowsError(try PrivateCorpusSelection(environment: ["PRIVATE_SOURCE_CORPUS_MODE": "live",
            "PRIVATE_SOURCE_CORPUS_FILE": "sources-01", "PRIVATE_SOURCE_CORPUS_LIMIT": "101"]))
    }

    func testInspectDefersObjectOptionsIncludingEncodedExecutableLiterals() {
        for address in [
            "/search,{method:(function(){throw new Error('must not execute');})()}",
            #"/search,{"method":"POST","body":"fixture"}"#,
            "/search,%7Bmethod%3A%28%27G%27%2B%27ET%27%29%7D",
            "/search@Header:X-Fixture=example"
        ] {
            let source = BookSource(bookSourceName: "Synthetic", bookSourceUrl: "https://private-probe.invalid", searchUrl: address)
            let entry = PrivateCorpusEntry(row: .init(fileId: "sources-01", fileSHA: String(repeating: "a", count: 64), index: 0), source: source)
            let row = PrivateCorpusRunner.inspect(entry)
            XCTAssertTrue(row.stages.contains { $0.stage == "search-request" && $0.status == "deferred" })
            XCTAssertFalse(row.stages.contains { $0.stage == "search-request" && $0.status == "constructed" })
        }
    }

    func testLiveUsesConfiguredSourceKeywordInActualRequestAndPrivateReport() async throws {
        let source = BookSource(bookSourceName: "Synthetic comic", bookSourceUrl: "https://private-probe.invalid",
            searchUrl: "/search?q={{key}}", ruleSearch: .init(fields: ["checkKeyWord": "  海贼王\n"]))
        let entry = PrivateCorpusEntry(row: .init(fileId: "sources-01", fileSHA: String(repeating: "a", count: 64), index: 0), source: source)
        let network = PrivateCorpusKeywordNetwork()
        let row = await PrivateCorpusRunner.probe(entry, keyword: "剑来", network: network)
        let requested = await network.keywords
        XCTAssertEqual(requested, ["海贼王"])
        XCTAssertEqual(row.keyword, "海贼王")
        let encoded = try JSONEncoder().encode(row)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertEqual(object["keyword"] as? String, "海贼王")
        for configured in ["", "  \n"] {
            let fallback = BookSource(bookSourceName: "Synthetic", bookSourceUrl: "https://private-probe.invalid",
                ruleSearch: .init(fields: ["checkKeyWord": configured]))
            XCTAssertEqual(PrivateCorpusRunner.searchKeyword(for: fallback, fallback: " 剑来\n"), "剑来")
        }
    }

    private func makeFixture(counts: [Int], invalidLastRow: Bool = false) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var files: [PrivateCorpusManifest.File] = []
        for (offset, count) in counts.enumerated() {
            let fileId = String(format: "sources-%02d", offset + 1)
            var objects: [Any] = (0..<count).map { _ in ["bookSourceName": "Synthetic", "bookSourceUrl": "https://private-probe.invalid"] }
            if invalidLastRow, offset == counts.count - 1 { objects[count - 1] = true }
            let bytes = try JSONSerialization.data(withJSONObject: objects)
            try bytes.write(to: directory.appendingPathComponent(fileId + ".json"))
            files.append(.init(fileId: fileId, relativePath: fileId + ".json", sha256: PrivateCorpusInput.digest(bytes),
                bytes: bytes.count, expectedCount: count))
        }
        let manifest = PrivateCorpusManifest(schemaVersion: 1, totalRecords: counts.reduce(0, +), files: files)
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("manifest.json"))
        return directory
    }
}

private struct PrivateCorpusManifest: Codable {
    struct File: Codable {
        let fileId: String
        let relativePath: String
        let sha256: String
        let bytes: Int
        let expectedCount: Int
    }
    let schemaVersion: Int
    let totalRecords: Int
    let files: [File]
}

private struct PrivateCorpusEntry: Sendable {
    let row: PrivateCorpusRow
    let source: BookSource?
}

private struct PrivateCorpusStage: Codable, Sendable {
    let stage: String
    let status: String
    var count = 0
    var deferredCount = 0
    var elapsedMilliseconds: Int?
    var failureCode: String?
    var message: String?
}

private struct PrivateCorpusRow: Codable, Sendable {
    let fileId: String
    let fileSHA: String
    let index: Int
    var status = "notRun"
    var coverage = "not-run"
    var keyword: String?
    var decodeFailure: String?
    var declaredMediaKind: Int?
    var resolvedMediaKind: Int?
    var hasLoginConfiguration = false
    var loginPersistenceVerified = false
    var playbackVerified = false
    var stages: [PrivateCorpusStage] = []
    var imageSamplePositions: [Int] = []
    var imageSampleDecoded: [Bool] = []
}

private struct PrivateCorpusReport: Encodable {
    let schemaVersion = 1
    let generatedAt = ISO8601DateFormatter().string(from: Date())
    let mode: String
    let selectedRecords: Int
    var rows: [PrivateCorpusRow]
    var totalRecords: Int { rows.count }

    private enum CodingKeys: String, CodingKey { case schemaVersion, generatedAt, mode, selectedRecords, rows, totalRecords }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(mode, forKey: .mode)
        try container.encode(selectedRecords, forKey: .selectedRecords)
        try container.encode(totalRecords, forKey: .totalRecords)
        try container.encode(rows, forKey: .rows)
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: [.atomic])
    }
}

private enum PrivateCorpusError: Error { case manifest, input, integrity, selection, output }

private struct PrivateCorpusInput {
    let directory: URL
    let manifest: PrivateCorpusManifest
    let entries: [PrivateCorpusEntry]

    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }

    static func confinedURL(_ relativePath: String, in directory: URL) throws -> URL {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/"), !relativePath.contains("\\"),
              !relativePath.split(separator: "/").contains("..") else { throw PrivateCorpusError.input }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let candidate = root.appendingPathComponent(relativePath).resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") else { throw PrivateCorpusError.input }
        return candidate
    }

    static func load(directory: URL) throws -> Self {
        let manifestURL = try confinedURL("manifest.json", in: directory)
        let manifest = try JSONDecoder().decode(PrivateCorpusManifest.self, from: boundedBytes(manifestURL, limit: 64 * 1024))
        guard manifest.schemaVersion == 1, manifest.files.count == 5,
              manifest.totalRecords > 0, manifest.totalRecords <= 10_000,
              manifest.files.allSatisfy({ (0...manifest.totalRecords).contains($0.expectedCount) }),
              Set(manifest.files.map(\.fileId)) == Set((1...5).map { String(format: "sources-%02d", $0) }) else {
            throw PrivateCorpusError.manifest
        }
        guard manifest.files.reduce(0, { $0 + $1.expectedCount }) == manifest.totalRecords else { throw PrivateCorpusError.integrity }
        var entries: [PrivateCorpusEntry] = []
        for file in manifest.files {
            guard file.expectedCount >= 0, file.bytes > 0, file.relativePath == file.fileId + ".json" else { throw PrivateCorpusError.manifest }
            let bytes = try boundedBytes(confinedURL(file.relativePath, in: directory), limit: 16 * 1024 * 1024)
            guard bytes.count == file.bytes, digest(bytes) == file.sha256.lowercased() else { throw PrivateCorpusError.integrity }
            guard let objects = try JSONSerialization.jsonObject(with: bytes) as? [Any], objects.count == file.expectedCount else {
                throw PrivateCorpusError.integrity
            }
            for (index, object) in objects.enumerated() {
                var row = PrivateCorpusRow(fileId: file.fileId, fileSHA: file.sha256.lowercased(), index: index)
                let source: BookSource?
                do {
                    let record = try JSONSerialization.data(withJSONObject: object, options: [.fragmentsAllowed])
                    source = try JSONDecoder().decode(BookSource.self, from: record)
                } catch { source = nil; row.decodeFailure = "record-decode-failed" }
                row.declaredMediaKind = source?.bookSourceType
                row.resolvedMediaKind = source.flatMap { $0.hasDynamicMediaType ? nil : $0.sourceKind.rawValue }
                row.hasLoginConfiguration = [source?.loginUrl, source?.loginUi, source?.loginCheckJs].compactMap { $0 }.contains { !$0.isEmpty }
                entries.append(.init(row: row, source: source))
            }
        }
        guard entries.count == manifest.totalRecords else { throw PrivateCorpusError.integrity }
        return .init(directory: directory, manifest: manifest, entries: entries)
    }

    private static func boundedBytes(_ url: URL, limit: Int) throws -> Data {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= limit else { throw PrivateCorpusError.input }
        let bytes = try Data(contentsOf: url)
        guard bytes.count <= limit else { throw PrivateCorpusError.input }
        return bytes
    }

    func outputURL(_ path: String?) throws -> URL {
        guard let path, path.hasPrefix("/"), path.hasSuffix(".json") else { throw PrivateCorpusError.output }
        let output = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().resolvingSymlinksInPath()
        let corpus = directory.resolvingSymlinksInPath().standardizedFileURL
        guard !output.path.hasPrefix(checkout.path + "/"), !output.path.hasPrefix(corpus.path + "/") else {
            throw PrivateCorpusError.output
        }
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        return output
    }
}

private struct PrivateCorpusSelection: Sendable {
    let mode: String
    let fileId: String?
    let start: Int
    let limit: Int
    let keyword: String

    init(environment: [String: String]) throws {
        mode = environment["PRIVATE_SOURCE_CORPUS_MODE"] ?? "inspect"
        fileId = environment["PRIVATE_SOURCE_CORPUS_FILE"]
        keyword = environment["PRIVATE_SOURCE_CORPUS_KEYWORD"] ?? "剑来"
        guard ["inspect", "live"].contains(mode), !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              keyword.utf8.count <= 256,
              let parsedStart = Int(environment["PRIVATE_SOURCE_CORPUS_START"] ?? "0"), parsedStart >= 0,
              let parsedLimit = Int(environment["PRIVATE_SOURCE_CORPUS_LIMIT"] ?? "25"), (1...100).contains(parsedLimit),
              mode != "live" || fileId != nil else { throw PrivateCorpusError.selection }
        start = parsedStart
        limit = parsedLimit
    }

    func positions(in entries: [PrivateCorpusEntry]) throws -> [Int] {
        if mode == "inspect" { return Array(entries.indices) }
        let selected = entries.indices.filter { entries[$0].row.fileId == fileId && entries[$0].row.index >= start }.prefix(limit)
        guard !selected.isEmpty else { throw PrivateCorpusError.selection }
        return Array(selected)
    }
}

private enum PrivateCorpusRunner {
    static func inspect(_ entry: PrivateCorpusEntry) -> PrivateCorpusRow {
        var row = entry.row
        row.coverage = "offline-structure-only"
        guard let source = entry.source else { row.status = "failed"; return row }
        row.status = "inspected"
        row.stages.append(.init(stage: "decode", status: "passed", count: 1))
        if let library = source.raw["jsLib"], !library.isEmpty {
            row.stages.append(.init(stage: "js-library", status: "deferred", deferredCount: 1))
        }
        for (stage, rule) in [("search-rules", source.ruleSearch), ("detail-rules", source.ruleBookInfo),
                              ("toc-rules", source.ruleToc), ("content-rules", source.ruleContent)] {
            guard let rule else { row.stages.append(.init(stage: stage, status: "notConfigured")); continue }
            let fragments = rule.fields.sorted { $0.key < $1.key }.map(\.value) + [rule.raw].compactMap { $0 }
            var observation = PrivateCorpusStage(stage: stage, status: "scanned")
            for fragment in fragments.prefix(96) {
                guard fragment.utf8.count <= 32 * 1024 else { observation.deferredCount += 1; continue }
                _ = RuleDirectiveParser.spans(in: fragment, marker: "@put:")
                _ = RuleDirectiveParser.spans(in: fragment, marker: "@get:")
                _ = RuleTransformParser.split(fragment)
                _ = RuleOperatorSplitter.firstOperator(in: fragment)
                observation.count += 1
                if LegadoRuleResolver().isJavaScriptRule(fragment) || fragment.contains("@js:")
                    || fragment.contains("<js>") || fragment.contains("{{") { observation.deferredCount += 1 }
            }
            observation.deferredCount += max(0, fragments.count - 96)
            row.stages.append(observation)
        }
        guard let address = source.searchUrl, !address.isEmpty else { return row }
        guard address.utf8.count <= 32 * 1024 else {
            row.stages.append(.init(stage: "search-request", status: "deferred", deferredCount: 1)); return row
        }
        let expanded = LegadoRuleResolver().interpolate(address, keyword: "fixture", page: 1, baseUrl: source.bookSourceUrl)
        let decodedAddress = expanded.removingPercentEncoding ?? expanded
        // Non-JSON request option objects enter SourceURLDirectiveParser's JS eval fallback.
        // Inspection only constructs plain URLs; even valid JSON options are deferred here.
        let hasOptions = !SearchURLResolver.splitURLAndDirectiveSuffix(decodedAddress).suffixPart.isEmpty
            || decodedAddress.contains("{") || decodedAddress.contains("}") || expanded.lowercased().contains("%7b")
        guard expanded.utf8.count <= 32 * 1024, !expanded.contains("@js:"), !expanded.contains("<js>"),
              !expanded.contains("\\"), !hasOptions, expanded.hasPrefix("http") || expanded.hasPrefix("/") else {
            row.stages.append(.init(stage: "search-request", status: "deferred", deferredCount: 1)); return row
        }
        let request = SourceRequestBuilder().buildSearchRequest(source: source, searchUrl: expanded, keyword: "fixture", page: 1)
        let valid = ["http", "https"].contains(request.url.scheme ?? "") && request.url.host != "invalid.local"
        row.stages.append(.init(stage: "search-request", status: valid ? "constructed" : "invalid", count: valid ? 1 : 0))
        return row
    }

    static func searchKeyword(for source: BookSource, fallback: String) -> String {
        let configured = source.ruleSearch?.fields["checkKeyWord"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return configured.isEmpty ? fallback.trimmingCharacters(in: .whitespacesAndNewlines) : configured
    }

    static func probe(_ entry: PrivateCorpusEntry, keyword: String,
                      network: SourceNetworkClient? = nil) async -> PrivateCorpusRow {
        await SourceRequestContext.$isDiagnostic.withValue(true) {
            var row = entry.row
            row.coverage = "first-result-first-chapter"
            guard let source = entry.source else { row.status = "failed"; return row }
            let actualKeyword = searchKeyword(for: source, fallback: keyword)
            row.keyword = actualKeyword
            guard actualKeyword.utf8.count <= 256 else {
                row.status = "failed"
                row.stages.append(.init(stage: "search", status: "failed", failureCode: "invalid-input",
                    message: "Configured checkKeyWord exceeds the 256-byte probe limit"))
                return row
            }
            // Every original record owns its cache even when two versions share a source URL.
            let cacheRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: cacheRoot) }
            let engine = LegadoSourceEngine(network: network, cookieStore: SourceCookieStore(storageURL: nil),
                browserLoginProvider: { _, _ in nil }, scriptCacheStore: SourceScriptCacheStore(rootURL: cacheRoot))
            engine.allowWebViewFallback = false
            let execution = await engine.runPipelineExecution(source: source, keyword: actualKeyword,
                timeout: 15, tocMaxPages: 1, contentMaxPages: 1)
            row.stages = execution.result.steps.map { step in
                .init(stage: step.stage.rawValue, status: step.status.rawValue, count: step.matchCount,
                    elapsedMilliseconds: step.elapsedMilliseconds, failureCode: step.failureCode?.rawValue,
                    message: step.responseSummary.map { String($0.prefix(2048)) })
            }
            row.resolvedMediaKind = execution.result.content?.chapter.mediaKind?.rawValue
                ?? execution.result.chapters.first?.mediaKind?.rawValue ?? execution.result.detail?.mediaKind?.rawValue
                ?? execution.result.searchBooks.first?.mediaKind?.rawValue ?? row.resolvedMediaKind
            if let error = execution.error {
                let stage = execution.result.steps.last?.stage.rawValue ?? "search"
                let kind = SourceDiagnosticClassifier.kind(error: error, stage: stage)
                row.status = kind == .authentication ? "requiresLogin" : "failed"
                return row
            }
            guard let content = execution.result.content else { row.status = "failed"; return row }
            let kind = content.chapter.mediaKind ?? execution.result.detail?.mediaKind
                ?? execution.result.searchBooks.first?.mediaKind ?? source.sourceKind
            row.resolvedMediaKind = kind.rawValue
            switch kind {
            case .comic:
                return await probeImages(content, source: source.resolvingMediaKind(kind), engine: engine, row: row)
            case .audio, .video:
                let reference = kind == .audio ? AudioContentParser.parseURL(content.text, base: content.chapter.url)
                    : VideoContentParser.parseVideoURL(from: content)
                row.status = reference == nil ? "failed" : "mediaExtracted"
                row.coverage = "media-url-extraction-only"
                row.stages.append(.init(stage: "media-extraction", status: reference == nil ? "failed" : "extracted",
                    count: reference == nil ? 0 : 1, failureCode: reference == nil ? "empty-result" : nil))
            case .text:
                row.status = execution.result.isComplete ? "passed" : "failed"
            }
            return row
        }
    }

    private static func probeImages(_ content: ChapterContent, source: BookSource,
                                    engine: LegadoSourceEngine, row initial: PrivateCorpusRow) async -> PrivateCorpusRow {
        var row = initial
        row.coverage = "first-chapter-first-middle-last-images"
        let pages = ComicContentParser.parsePages(from: content)
        guard !pages.isEmpty else {
            row.status = "failed"
            row.stages.append(.init(stage: "image-parse", status: "failed", failureCode: "empty-result"))
            return row
        }
        let sourceHeaders: [String: String]
        let resolvedHeaders = ComicChapterRequestBuilder.needsNetworkHeaders(for: ComicChapterResources(content: content))
            ? await SourceImageRequestHeaders.resolve(engine: engine, source: source, chapter: content.chapter)
            : .success([:])
        switch resolvedHeaders {
        case .success(let headers): sourceHeaders = headers
        case .failure(let error):
            row.status = "failed"
            row.stages.append(.init(stage: "image-headers", status: "failed", failureCode: "header-resolution",
                message: error.displayMessage))
            return row
        }
        let context = SourceImageDecodeContext.resolve(source: source, chapter: content.chapter, engine: engine)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = ComicImageTimeoutPolicy.defaultRequest
        configuration.timeoutIntervalForResource = ComicImageTimeoutPolicy.defaultResource
        let loader = RemoteImageLoader(configuration: configuration)
        defer { loader.clearCache() }
        let positions = Array(Set([0, pages.count / 2, pages.count - 1])).sorted()
        for position in positions {
            let page = pages[position]
            let headers = ComicImageRequest(url: page.url, headers: page.headers).mergingHeaders(sourceHeaders, chapterURL: content.chapter.url)
            let request = await SourceImageRequestHeaders.addingSessionCookies(
                to: ComicImageRequest(url: page.url, headers: headers, decodeContext: context), engine: engine)
            let result = await AsyncTimeout.run(seconds: 12) {
                guard let url = URL(string: request.url) else { return Result<UIImage, ComicImageFailure>.failure(.invalidResponse) }
                return await loader.comicPage(for: url, headers: request.headers,
                    maxPixelSize: ComicPagePositionPolicy.maxImagePixels, decodeContext: request.decodeContext)
            }
            let decoded: Bool
            let failure: String?
            switch result {
            case .success?: decoded = true; failure = nil
            case .failure(let error)?: decoded = false; failure = error.message
            case nil: decoded = false; failure = "image-timeout"
            }
            row.imageSamplePositions.append(position)
            row.imageSampleDecoded.append(decoded)
            row.stages.append(.init(stage: "image-decode", status: decoded ? "passed" : "failed", count: decoded ? 1 : 0,
                failureCode: decoded ? nil : "image-transport-or-decode", message: failure))
        }
        row.status = row.imageSampleDecoded.allSatisfy { $0 } ? "passed" : "failed"
        return row
    }
}

private actor PrivateCorpusKeywordNetwork: SourceNetworkClient {
    private(set) var keywords: [String] = []

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        if let keyword = URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value {
            keywords.append(keyword)
        }
        return .failure(.unsupported("Synthetic keyword capture completed without HTTP"))
    }
}
