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
        XCTAssertEqual(sources.count, 1107, "search-url-corpus is incomplete")

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
                    if let issue = Self.classify(url, base: source.bookSourceUrl) {
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

    /// A resolved URL that cannot be handed to `URLSession` as-is.
    ///
    /// Legado allows a scheme-less `searchUrl` (resolved against
    /// `bookSourceUrl`), and its optional `,{...}` request options are not part
    /// of the URL. Both are normal, so classify only the URL part after
    /// splitting the options and resolving it exactly like the request layer.
    static func classify(_ url: String, base: String) -> String? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "empty" }
        if trimmed.lowercased().hasPrefix("data:") { return nil }

        let split = SearchURLResolver.splitURLAndDirectiveSuffix(trimmed)
        let address = split.urlPart.trimmingCharacters(in: .whitespacesAndNewlines)
        if address.isEmpty { return "emptyAddress" }
        if address.lowercased().hasPrefix("data:") { return nil }
        if address.contains("{{") || address.contains("}}") { return "braceResidue" }
        if address.contains("<js>") || address.contains("</js>") { return "jsResidue" }
        if address.contains("%3C") || address.contains("%3E") { return "encodedAngle" }
        if address.contains("<") || address.contains(">") { return "angleResidue" }

        let resolved = SourceRequestBuilder().resolveURL(address, relativeTo: base)
        if resolved.host == "invalid.local" { return "invalidBase" }
        guard let scheme = resolved.scheme?.lowercased() else { return "unparseable" }
        guard scheme == "http" || scheme == "https" else { return "nonNetworkScheme" }
        if (resolved.host ?? "").isEmpty { return "missingHost" }
        if let fragment = resolved.fragment,
           fragment.contains("/") || fragment.contains("?") {
            return "fragmentSwallowsPath"
        }
        return nil
    }

    func testClassifierAcceptsRelativeURLAndLegadoOptions() {
        XCTAssertNil(Self.classify("/api/v5/search/words?wd=x", base: "https://api-bc.wtzw.com"))
        XCTAssertNil(Self.classify("https://api-bc.wtzw.com/api/search?wd=x,{\"headers\":{\"sign\":\"abc\"}}", base: "https://api-bc.wtzw.com"))
        XCTAssertNil(Self.classify("http://wap.4pan.org#/s.php,{\"method\":\"POST\"}", base: "http://wap.4pan.org#"))
        XCTAssertNil(Self.classify("search.php?q=x", base: "https://example.com/"))
    }

    func testClassifierStillFlagsUnresolvedTemplates() {
        XCTAssertEqual(Self.classify("/search?q={{key}}", base: "https://example.com"), "braceResidue")
        XCTAssertEqual(Self.classify("/search?q=<js>result</js>", base: "https://example.com"), "jsResidue")
    }
}
