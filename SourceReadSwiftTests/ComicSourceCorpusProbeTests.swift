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
        var imageCount = 0
        var decoded = false
        var elapsedSeconds = 0.0
    }

    private func probe(_ source: BookSource, index: Int) async -> Row {
        await SourceRequestContext.$isDiagnostic.withValue(true) {
            let start = Date()
            var row = Row(index: index, name: source.bookSourceName)
            let engine = LegadoSourceEngine()
            let result = await engine.runPipelineExecution(source: source, keyword: "斗罗", timeout: 8, tocMaxPages: 1, contentMaxPages: 1)
            row.elapsedSeconds = Date().timeIntervalSince(start)
            if let error = result.error {
                row.stage = result.result.steps.last?.stage.rawValue ?? "search"
                row.message = String(error.displayMessage.prefix(200))
                return row
            }
            guard let content = result.result.content else { row.stage = "content"; row.message = "No chapter content"; return row }
            let pages = ComicContentParser.parsePages(from: content)
            row.stage = "image-parse"; row.imageCount = pages.count
            guard let first = pages.first, let imageURL = URL(string: first.url) else { row.message = "No image URL extracted"; return row }
            let sourceHeaders = SourceRequestBuilder().imageRequestHeaders(for: source, chapterURL: content.chapter.url)
            let headers = ComicImageRequest(url: first.url, headers: first.headers).mergingHeaders(sourceHeaders, chapterURL: content.chapter.url)
            row.stage = "image-decode"
            let image = await AsyncTimeout.run(seconds: 10) { await RemoteImageLoader.shared.image(for: imageURL, headers: headers) }
            row.decoded = image.flatMap { $0 } != nil
            row.message = row.decoded ? "First chapter / first image decoded (not all chapters verified)" : "Image request or bitmap decode failed"
            row.elapsedSeconds = Date().timeIntervalSince(start)
            return row
        }
    }
}
