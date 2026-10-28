import XCTest
@testable import SourceReadSwift

/// Pins the 七猫 (`api-bc.wtzw.com`) signature source to the algorithm
/// documented in `七猫纯小说_接口算法与鉴权分析.md`:
/// `sign = MD5(sorted "k=v" concatenation + "d3dGiJc651gSQ8w1")`.
///
/// The source is a 1.1 KB `@js:` program. Passing this test means the
/// JavaScript bridge (`java.md5Encode`, `Object.keys().sort()`, array reduce,
/// `java.put`) matches Legado byte for byte, not merely that the resolver
/// returned a URL.
final class QimaoSignatureTests: XCTestCase {
    private func qimaoSource() throws -> BookSource {
        let directory = TestFixtureSupport.directory("search-url-corpus")
        let data = try Data(contentsOf: directory.appendingPathComponent("sources.json"))
        let sources = try JSONDecoder().decode([BookSource].self, from: data)
        guard let source = sources.first(where: { $0.bookSourceUrl.contains("api-bc.wtzw.com") }) else {
            throw XCTSkip("七猫 source is missing from search-url-corpus")
        }
        return source
    }

    private func resolve(_ source: BookSource, page: Int) -> String? {
        switch SearchURLResolver().resolve(source: source, keyword: "剑来", page: page) {
        case .success(let url): return url
        case .failure: return nil
        }
    }

    func testParamSignatureMatchesDocumentedAlgorithm() throws {
        let source = try qimaoSource()

        guard let page1 = resolve(source, page: 1) else {
            return XCTFail("page 1 did not resolve")
        }
        XCTAssertTrue(page1.contains("sign=0c85373002b897710cae9b8aff9a60a5"), page1)

        guard let page2 = resolve(source, page: 2) else {
            return XCTFail("page 2 did not resolve")
        }
        XCTAssertTrue(page2.contains("sign=5e2dd3b0eeb9b5a00333455858002d44"), page2)
        XCTAssertFalse(page2.contains("page=1"), page2)
    }

    func testHeaderSignatureMatchesDocumentedAlgorithm() throws {
        let source = try qimaoSource()
        guard let url = resolve(source, page: 1) else {
            return XCTFail("page 1 did not resolve")
        }
        XCTAssertTrue(url.contains("\"sign\":\"fc697243ab534ebaf51d2fa80f251cb4\""), url)
    }
}