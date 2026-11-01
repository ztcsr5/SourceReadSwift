import Foundation
import UIKit
import XCTest
@testable import SourceReadSwift

/// Opt-in live checks are evidence, not a deterministic pass/fail assertion.
/// A healthy homepage is never counted as a decoded comic page. No login or
/// purchase actions are executed; JS rules run in the normal diagnostic mode.
final class ComicSourceCorpusProbeTests: XCTestCase {
    func testEveryProvidedComicSourceThroughImageDecode() async throws {
        guard ProcessInfo.processInfo.environment["COMIC_CORPUS_PROBE"] == "1" else {
            throw XCTSkip("Live comic audit is opt-in; deterministic parser/image fixtures run normally")
        }
        let url = try XCTUnwrap(TestFixtureSupport.url(name: "comic-sources-20261101", extension: "json", subdirectory: "Fixtures"))
        let sources = try JSONDecoder().decode([BookSource].self, from: Data(contentsOf: url))
        XCTAssertEqual(sources.count, 31)
        var reports: [Row] = []
        await withTaskGroup(of: Row.self) { group in
            var iterator = sources.enumerated().makeIterator()
            for _ in 0..<3 { if let (i,source) = iterator.next() { group.addTask { await self.probe(source, index: i) } } }
            while let row = await group.next() {
                reports.append(row)
                print("COMIC_AUDIT index=\(row.index) stage=\(row.stage) images=\(row.imageCount) decoded=\(row.decoded)")
                if let data = try? JSONEncoder().encode(row) { print("COMIC_ROW_B64 " + data.base64EncodedString()) }
                if let (i,source) = iterator.next() { group.addTask { await self.probe(source, index: i) } }
            }
        }
        let data = try JSONEncoder().encode(reports.sorted { $0.index < $1.index })
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "comic-source-pipeline-31"; attachment.lifetime = .keepAlways; add(attachment)
        XCTAssertEqual(reports.count, 31, "Every source must leave a result even if unavailable")
    }

    private struct Row: Codable, Sendable {
        let index: Int
        let name: String
        var stage: String = "search"
        var message: String = ""
        var keyword: String = ""
        var searchCount = 0
        var chapterCount = 0
        var chapterTitle: String = ""
        var contentPreview: String = ""
        var firstImageURL: String = ""
        var imageCount = 0
        var decoded = false
        var failureKind = ""
        var sampledPositions: [Int] = []
        var sampledDecoded: [Bool] = []
        var responseStatus: Int?
        var responseType: String?
        var responseSnippet: String?
        var elapsedSeconds = 0.0
    }

    private func probe(_ source: BookSource, index: Int) async -> Row {
        await SourceRequestContext.$isDiagnostic.withValue(true) {
            let start = Date()
            var row = Row(index: index, name: source.bookSourceName)
            let engine = LegadoSourceEngine()
            let configured = source.ruleSearch?.fields["checkKeyWord"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            row.keyword = configured.isEmpty ? "斗罗" : configured
            let result = await engine.runPipelineExecution(source: source, keyword: row.keyword, timeout: 8, tocMaxPages: 1, contentMaxPages: 1)
            row.searchCount = result.result.searchBooks.count
            row.chapterCount = result.result.chapters.count
            row.chapterTitle = result.result.chapters.first?.title ?? ""
            row.elapsedSeconds = Date().timeIntervalSince(start)
            if let error = result.error {
                row.stage = result.result.steps.last?.stage.rawValue ?? "search"
                row.failureKind = SourceDiagnosticClassifier.kind(error: error, stage: row.stage).rawValue
                if let step = result.result.steps.last,
                   let evidence = engine.diagnosticEvidence(sourceURL: source.bookSourceUrl, stage: step.stage) {
                    row.responseStatus = evidence.responseStatusCode
                    row.responseType = evidence.responseHeaders.first { $0.key.lowercased() == "content-type" }?.value
                    row.responseSnippet = evidence.responseSnippet.map { String(SourceDiagnosticRedactor.value($0).prefix(400)) }
                    if let sniffed = SourceDiagnosticClassifier.sniffSnippet(snippet: evidence.responseSnippet,
                        statusCode: evidence.responseStatusCode, decodedByteCount: evidence.responseDecodedByteCount, stage: row.stage) {
                        row.failureKind = sniffed.kind.rawValue
                        row.message = sniffed.summary
                        return row
                    }
                }
                row.message = String(error.displayMessage.prefix(200))
                return row
            }
            guard let content = result.result.content else { row.stage = "content"; row.message = "No chapter content"; return row }
            row.contentPreview = String(content.paragraphs.prefix(2).joined(separator: "\n").prefix(400))
            let pages = ComicContentParser.parsePages(from: content)
            row.stage = "image-parse"; row.imageCount = pages.count
            guard let first = pages.first else {
                row.failureKind = "not-image-payload"
                row.message = "No image URL extracted; homepage, source guard, empty list or non-image media must not count as a bitmap failure"
                return row
            }
            row.firstImageURL = first.url
            let sourceHeaders = SourceRequestBuilder().imageRequestHeaders(for: source, chapterURL: content.chapter.url)
            row.stage = "image-decode"
            let positions = Array(Set([0, pages.count / 2, pages.count - 1])).sorted()
            for position in positions {
                let page = pages[position]
                let headers = ComicImageRequest(url: page.url, headers: page.headers).mergingHeaders(sourceHeaders, chapterURL: content.chapter.url)
                let imageURL = URL(string: page.url)
                let image = await AsyncTimeout.run(seconds: 10) {
                    guard let imageURL else { return UIImage?.none }
                    return await RemoteImageLoader.shared.image(for: imageURL, headers: headers)
                }
                row.sampledPositions.append(position)
                row.sampledDecoded.append(image.flatMap { $0 } != nil)
            }
            row.decoded = row.sampledDecoded.first == true
            row.failureKind = row.sampledDecoded.allSatisfy { $0 } ? "" : "image-transport-or-decode"
            row.message = "First chapter sampled first/middle/last: \(row.sampledDecoded.filter { $0 }.count)/\(positions.count) decoded; not all chapters/pages verified"
            row.elapsedSeconds = Date().timeIntervalSince(start)
            return row
        }
    }
}
