import XCTest
@testable import SourceReadSwift

/// Every search URL in the 997-source bank, resolved by the real
/// `SearchURLResolver` instead of a Python re-implementation.
///
/// The corpus intentionally contains sources that are expected to stay broken
/// (dead hosts, `@js:` URLs, data URLs). The probe's job is to classify what
/// the resolver produces, so a URL-layer defect is separated from a site that
/// simply has nothing to return. It writes `search-url-probe.json` when
/// `SEARCH_URL_PROBE_OUTPUT` is set and never fails on a per-source issue.
final class SourceSearchURLProbeTests: XCTestCase {
    private struct Entry: Decodable {
        let bookSourceName: String
        let bookSourceUrl: String
        let searchUrl: String?
    }

    func testSearchURLBank() throws {
        let directory = TestFixtureSupport.directory("search-url-corpus")
        let data = try Data(contentsOf: directory.appendingPathComponent("sources.json"))
        let sources = try JSONDecoder().decode([BookSource].self, from: data)
        XCTAssertEqual(sources.count, 997, "search-url-corpus is incomplete")

        let resolver = SearchURLResolver()
        var report: [[String: Any]] = []
        var issueCounts: [String: Int] = [:]
        var issueSamples: [String] = []
        var resolvedCount = 0

        for (index, source) in sources.enumerated() {
            guard let searchUrl = source.searchUrl, !searchUrl.isEmpty else { continue }
            var entry: [String: Any] = [
                "i": index,
                "name": source.bookSourceName,
                "base": source.bookSourceUrl,
                "searchUrl": searchUrl
            ]

            for page in [1, 2] {
                let key = page == 1 ? "page1" : "page2"
                switch resolver.resolve(source: source, keyword: "\u{5251}\u{6765}", page: page) {
                case .success(let url):
                    entry[key] = url
                    resolvedCount += 1
                    if let issue = Self.classify(url) {
                        entry[key + "Issue"] = issue
                        issueCounts[issue, default: 0] += 1
                        if issueSamples.count < 40 {
                            issueSamples.append("\(page) \(source.bookSourceName) :: \(issue) :: \(url.prefix(120))")
                        }
                    }
                case .failure(let error):
                    entry[key + "Error"] = String(describing: error)
                    issueCounts["error", default: 0] += 1
                }
            }
            report.append(entry)
        }

        let output = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        if let path = ProcessInfo.processInfo.environment["SEARCH_URL_PROBE_OUTPUT"], !path.isEmpty {
            try output.write(to: URL(fileURLWithPath: path))
        }

        print("SEARCH_URL_CORPUS sources=\(report.count) resolved=\(resolvedCount)")
        for key in issueCounts.keys.sorted() {
            print("SEARCH_URL_ISSUE \(key)=\(issueCounts[key] ?? 0)")
        }
        for sample in issueSamples {
            print("SEARCH_URL_SAMPLE \(sample)")
        }
        XCTAssertEqual(report.count, sources.filter { !($0.searchUrl ?? "").isEmpty }.count)
    }

    /// A resolved URL that cannot be handed to `URLSession` as-is. Anything
    /// left here is a resolver gap, not a site problem.
    private static func classify(_ url: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "empty" }
        if trimmed.contains("{{") || trimmed.contains("}}") { return "braceResidue" }
        if trimmed.contains("<js>") || trimmed.contains("</js>") { return "jsResidue" }
        if trimmed.contains("%3C") || trimmed.contains("%3E") { return "encodedAngle" }
        if trimmed.contains("<") || trimmed.contains(">") { return "angleResidue" }
        if let hash = trimmed.firstIndex(of: "#") {
            let tail = trimmed[hash...].dropFirst()
            if tail.contains("/") || tail.contains("?") { return "fragmentSwallowsPath" }
        }
        guard let parsed = URL(string: trimmed), let scheme = parsed.scheme else { return "unparseable" }
        if scheme == "data" { return nil }
        guard scheme == "http" || scheme == "https" else { return "nonNetworkScheme" }
        if (parsed.host ?? "").isEmpty { return "missingHost" }
        return nil
    }
}
