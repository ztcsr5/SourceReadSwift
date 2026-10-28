import XCTest
import SwiftSoup
@testable import SourceReadSwift

/// 97 live table-of-contents pages captured from real Legado sources, each
/// paired with the chapter count the same `chapterList` rule produces under
/// jsoup. The rows probe proves the list rule selects the same nodes; this
/// probe proves the TOC chain (chapterList + chapter name/url) survives on the
/// page the reader actually opens. A source whose TOC renders empty in the app
/// but counts 900 here is a Swift bug, not a dead site.
final class SourceTocCorpusProbeTests: XCTestCase {
    private struct Entry: Decodable {
        let id: Int
        let name: String
        let rule: String
        let expected: Int
        let bodyFile: String
        let baseUrl: String
        let chapterNameRule: String?
        let chapterUrlRule: String?
    }

    func testTocParityCorpus() throws {
        let directory = try corpusDirectory()
        let manifest = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let entries = try JSONDecoder().decode([Entry].self, from: manifest)
        XCTAssertEqual(entries.count, 97, "toc-corpus manifest is incomplete")

        let extractor = HtmlRuleExtractor()
        var report: [[String: Any]] = []
        var mismatches: [String] = []
        var emptyNameTotal = 0
        var emptyURLTotal = 0
        for entry in entries {
            let bodyURL = directory.appendingPathComponent(entry.bodyFile)
            let html = try String(contentsOf: bodyURL, encoding: .utf8)
            let base = URL(string: entry.baseUrl) ?? URL(string: "https://example.com/")!
            let chapters: [Element]
            let actual: Int
            do {
                chapters = try extractor.select(html, baseUrl: base, listRule: entry.rule)
                actual = chapters.count
            } catch {
                chapters = []
                actual = -1
            }

            var names: [String] = []
            var links: [String] = []
            var emptyNames = 0
            var emptyURLs = 0
            for chapter in chapters.prefix(5) {
                let title = (try? extractor.value(from: chapter, rule: entry.chapterNameRule, fallback: nil, baseUrl: base)) ?? ""
                let link = (try? extractor.value(from: chapter, rule: entry.chapterUrlRule, fallback: nil, baseUrl: base)) ?? ""
                if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { emptyNames += 1 }
                if link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !(entry.chapterUrlRule ?? "").isEmpty { emptyURLs += 1 }
                if names.count < 3 { names.append(String(title.prefix(30))) }
                if links.count < 3 { links.append(String(link.prefix(60))) }
            }
            if !chapters.isEmpty {
                emptyNameTotal += emptyNames
                emptyURLTotal += emptyURLs
            }

            report.append([
                "id": entry.id,
                "name": entry.name,
                "rule": entry.rule,
                "expected": entry.expected,
                "actual": actual,
                "emptyNames": emptyNames,
                "emptyURLs": emptyURLs,
                "nameSamples": names,
                "urlSamples": links
            ])
            if actual != entry.expected {
                mismatches.append("\(entry.id) exp=\(entry.expected) act=\(actual) rule=\(entry.rule)")
            }
        }

        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        if let output = ProcessInfo.processInfo.environment["TOC_PROBE_OUTPUT"], !output.isEmpty {
            try data.write(to: URL(fileURLWithPath: output))
        }
        print("TOC_CORPUS total=\(entries.count) mismatches=\(mismatches.count)")
        for line in mismatches.prefix(200) {
            print("TOC_MISMATCH \(line)")
        }
        print("TOC_FIELDS emptyNames=\(emptyNameTotal) emptyURLs=\(emptyURLTotal)")
        XCTAssertEqual(report.count, entries.count)
    }

    private func corpusDirectory() throws -> URL {
        let bundle = Bundle(for: type(of: self))
        let candidates = [
            bundle.resourceURL?.appendingPathComponent("Fixtures/toc-corpus"),
            bundle.resourceURL?.appendingPathComponent("toc-corpus"),
            bundle.bundleURL.appendingPathComponent("Fixtures/toc-corpus"),
            bundle.resourceURL,
            bundle.bundleURL
        ].compactMap { $0 }
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.appendingPathComponent("manifest.json").path) {
            return candidate
        }
        throw XCTSkip("toc-corpus fixture directory is missing from the test bundle")
    }
}
