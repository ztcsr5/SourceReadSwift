import XCTest
import SwiftSoup
@testable import SourceReadSwift

/// 114 real search responses captured from live Legado sources, each paired
/// with the row count the same `bookList` rule produces under jsoup (the
/// reference Legado uses). The probe writes a JSON report when
/// `ROWS_PROBE_OUTPUT` is present so `.github/workflows/source-rows-probe.yml`
/// can upload it; CI then diffs SwiftSoup selection against jsoup instead of
/// guessing why a search page came back empty.
final class SourceRowsCorpusProbeTests: XCTestCase {
    private struct Entry: Decodable {
        let id: Int
        let name: String
        let rule: String
        let expected: Int
        let bodyFile: String
        let baseUrl: String
    }

    func testRowsParityCorpus() throws {
        let directory = try corpusDirectory()
        let manifest = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        let entries = try JSONDecoder().decode([Entry].self, from: manifest)
        XCTAssertEqual(entries.count, 114, "rows-corpus manifest is incomplete")

        let extractor = HtmlRuleExtractor()
        var report: [[String: Any]] = []
        var mismatches: [String] = []
        for entry in entries {
            let bodyURL = directory.appendingPathComponent(entry.bodyFile)
            let html = try String(contentsOf: bodyURL, encoding: .utf8)
            let base = URL(string: entry.baseUrl) ?? URL(string: "https://example.com/")!
            let actual: Int
            do {
                actual = try extractor.select(html, baseUrl: base, listRule: entry.rule).count
            } catch {
                actual = -1
            }
            report.append([
                "id": entry.id,
                "name": entry.name,
                "rule": entry.rule,
                "expected": entry.expected,
                "actual": actual
            ])
            if actual != entry.expected {
                mismatches.append("\(entry.id) exp=\(entry.expected) act=\(actual) rule=\(entry.rule)")
            }
        }

        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        if let output = ProcessInfo.processInfo.environment["ROWS_PROBE_OUTPUT"], !output.isEmpty {
            try data.write(to: URL(fileURLWithPath: output))
        }
        print("ROWS_CORPUS total=\(entries.count) mismatches=\(mismatches.count)")
        for line in mismatches.prefix(200) {
            print("ROWS_MISMATCH \(line)")
        }
        XCTAssertEqual(report.count, entries.count)
    }

    private func corpusDirectory() throws -> URL {
        let bundle = Bundle(for: type(of: self))
        let candidates = [
            bundle.resourceURL?.appendingPathComponent("Fixtures/rows-corpus"),
            bundle.resourceURL?.appendingPathComponent("rows-corpus"),
            bundle.bundleURL.appendingPathComponent("Fixtures/rows-corpus"),
            bundle.resourceURL,
            bundle.bundleURL
        ].compactMap { $0 }
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.appendingPathComponent("manifest.json").path) {
            return candidate
        }
        throw XCTSkip("rows-corpus fixture directory is missing from the test bundle")
    }
}