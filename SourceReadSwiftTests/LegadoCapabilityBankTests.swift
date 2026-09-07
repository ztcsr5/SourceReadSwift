import Foundation
import XCTest

final class LegadoCapabilityBankTests: XCTestCase {
    func testCapabilityBankSnapshotMatchesExpectedCoverageProfile() throws {
        let sources = try loadFixture()
        XCTAssertEqual(sources.count, 13)

        var counts: [String: Int] = [:]
        for source in sources {
            let labels = labels(for: source)
            XCTAssertTrue(labels.contains("Search"))
            XCTAssertTrue(labels.contains("Detail"))
            XCTAssertTrue(labels.contains("TOC"))
            XCTAssertTrue(labels.contains("Content"))
            for label in labels {
                counts[label, default: 0] += 1
            }
        }

        XCTAssertEqual(counts["Search"], 13)
        XCTAssertEqual(counts["Detail"], 13)
        XCTAssertEqual(counts["TOC"], 13)
        XCTAssertEqual(counts["Content"], 13)
        XCTAssertEqual(counts["Explore"], 10)
        XCTAssertEqual(counts["CookieJar"], 10)
        XCTAssertEqual(counts["JS-heavy"], 8)
        XCTAssertEqual(counts["POST-search"], 7)
        XCTAssertEqual(counts["GBK"], 4)
        XCTAssertEqual(counts["Login/CF-check"], 3)
        XCTAssertEqual(counts["Crypto/AES/Base64"], 3)
        XCTAssertEqual(counts["Font-obf/Image-text"], 3)
        XCTAssertEqual(counts["Paging"], 13)
    }

    private func loadFixture() throws -> [[String: Any]] {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: "legado-capability-bank-20260908", withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: "legado-capability-bank-20260908", withExtension: "json")
        )
        let data = try Data(contentsOf: url)
        let raw = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(raw as? [[String: Any]])
    }

    private func labels(for source: [String: Any]) -> [String] {
        let sourceText = prettyJSONString(source)
        var labels = ["Search", "Detail", "TOC", "Content"]

        if (source["enabledExplore"] as? Bool) == true,
           let exploreUrl = source["exploreUrl"] as? String,
           !exploreUrl.isEmpty {
            labels.append("Explore")
        }
        if ((source["searchUrl"] as? String) ?? "").uppercased().contains("POST") {
            labels.append("POST-search")
        }
        if (source["enabledCookieJar"] as? Bool) == true {
            labels.append("CookieJar")
        }
        if containsAny(sourceText, ["<js>", "@js:", "java.", "source.getVariable"]) {
            labels.append("JS-heavy")
        }
        if containsAny(sourceText, ["startBrowserAwait", "Just a moment", "验证"]) {
            labels.append("Login/CF-check")
        }
        if containsAny(sourceText, ["createSymmetricCrypto", "AES", "md5Encode", "base64Decode"]) {
            labels.append("Crypto/AES/Base64")
        }
        if containsAny(sourceText, ["queryTTF", "charCodeAt", "字体", "toimg"]) {
            labels.append("Font-obf/Image-text")
        }
        if containsAny(sourceText, ["{{page}}", "nextTocUrl", "nextContentUrl"]) {
            labels.append("Paging")
        }
        if sourceText.uppercased().contains("GBK") {
            labels.append("GBK")
        }

        return labels
    }

    private func prettyJSONString(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) else {
            return String(describing: value)
        }
        return String(data: data, encoding: .utf8) ?? String(describing: value)
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
