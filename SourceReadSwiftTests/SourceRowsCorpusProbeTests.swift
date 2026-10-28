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
        let nameRule: String?
        let authorRule: String?
        let coverRule: String?
        let bookUrlRule: String?
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
            let rows: [Element]
            let actual: Int
            do {
                rows = try extractor.select(html, baseUrl: base, listRule: entry.rule)
                actual = rows.count
            } catch {
                rows = []
                actual = -1
            }

            // Field-level pass: rows alone say nothing about whether the row
            // turns into a usable book. A rule that selects 50 elements but
            // yields 50 empty names is the "search returns nothing" report.
            var emptyNames = 0
            var emptyAuthors = 0
            var emptyCovers = 0
            var emptyBookURLs = 0
            var nameSamples: [String] = []
            var authorSamples: [String] = []
            var bookURLSamples: [String] = []
            for row in rows.prefix(5) {
                let name = (try? extractor.value(from: row, rule: entry.nameRule, fallback: nil, baseUrl: base)) ?? ""
                let author = (try? extractor.value(from: row, rule: entry.authorRule, fallback: nil, baseUrl: base)) ?? ""
                let cover = (try? extractor.value(from: row, rule: entry.coverRule, fallback: nil, baseUrl: base)) ?? ""
                let link = (try? extractor.value(from: row, rule: entry.bookUrlRule, fallback: nil, baseUrl: base)) ?? ""
                if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { emptyNames += 1 }
                if author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !(entry.authorRule ?? "").isEmpty { emptyAuthors += 1 }
                if cover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !(entry.coverRule ?? "").isEmpty { emptyCovers += 1 }
                if link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !(entry.bookUrlRule ?? "").isEmpty { emptyBookURLs += 1 }
                if nameSamples.count < 3 { nameSamples.append(String(name.prefix(40))) }
                if authorSamples.count < 3 { authorSamples.append(String(author.prefix(20))) }
                if bookURLSamples.count < 3 { bookURLSamples.append(String(link.prefix(60))) }
            }

            report.append([
                "id": entry.id,
                "name": entry.name,
                "rule": entry.rule,
                "expected": entry.expected,
                "actual": actual,
                "emptyNames": emptyNames,
                "emptyAuthors": emptyAuthors,
                "emptyCovers": emptyCovers,
                "emptyBookURLs": emptyBookURLs,
                "nameSamples": nameSamples,
                "authorSamples": authorSamples,
                "bookURLSamples": bookURLSamples
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
        var emptyNameTotal = 0
        var emptyAuthorTotal = 0
        var emptyBookURLTotal = 0
        for item in report {
            emptyNameTotal += (item["emptyNames"] as? Int) ?? 0
            emptyAuthorTotal += (item["emptyAuthors"] as? Int) ?? 0
            emptyBookURLTotal += (item["emptyBookURLs"] as? Int) ?? 0
        }
        print("ROWS_FIELDS emptyNames=\(emptyNameTotal) emptyAuthors=\(emptyAuthorTotal) emptyBookURLs=\(emptyBookURLTotal)")
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