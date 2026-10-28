import XCTest
@testable import SourceReadSwift

/// End-to-end search parsing against responses captured from live Legado
/// sources.  Every `*.body` file is the byte-for-byte answer of the real site
/// for the keyword in `index.json`; `expectedMinimum` is how many result rows
/// the same `ruleSearch` block yields under Legado semantics.  The test fails
/// when our parser returns fewer rows, which is exactly the "search is empty"
/// regression users report.
final class RealSourceSearchRegressionTests: XCTestCase {
    private struct Fixture: Decodable {
        let name: String
        let bookSourceUrl: String?
        let keyword: String
        let contentType: String
        let charset: String
        let bodyFile: String
        let expectedMinimum: Int
        let source: BookSource
    }

    private func fixtureDirectory() throws -> URL {
        let bundle = Bundle(for: type(of: self))
        // XcodeGen may keep the folder reference or flatten every fixture into
        // the bundle root, so probe both shapes and pick whichever holds the index.
        let candidates = [
            TestFixtureSupport.directory("real-sources"),
            bundle.resourceURL?.appendingPathComponent("Fixtures/real-sources"),
            bundle.resourceURL?.appendingPathComponent("real-sources"),
            bundle.bundleURL.appendingPathComponent("Fixtures/real-sources"),
            bundle.resourceURL,
            bundle.bundleURL
        ].compactMap { $0 }
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.appendingPathComponent("index.json").path) {
            return candidate
        }
        throw XCTSkip("real-sources fixture directory is missing from the test bundle")
    }

    func testCapturedSourcesReturnAtLeastTheirExpectedRows() throws {
        let directory = try fixtureDirectory()
        let indexData = try Data(contentsOf: directory.appendingPathComponent("index.json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: indexData)
        XCTAssertFalse(fixtures.isEmpty, "fixture index decoded to zero entries")

        var failures: [String] = []
        for fixture in fixtures {
            let bodyURL = directory.appendingPathComponent(fixture.bodyFile)
            guard let bodyData = try? Data(contentsOf: bodyURL) else {
                failures.append("\(fixture.name): missing \(fixture.bodyFile)")
                continue
            }
            let headers = ["Content-Type": fixture.contentType]
            let text = ResponseTextDecoder().decode(
                data: bodyData,
                headers: headers,
                preferredCharset: fixture.charset
            )
            let response = SourceResponse(
                url: URL(string: fixture.bookSourceUrl ?? "https://example.com")!,
                statusCode: 200,
                headers: headers,
                body: text,
                data: bodyData
            )
            let result = SearchResultParser().parse(
                source: fixture.source,
                response: response,
                keyword: fixture.keyword
            )
            switch result {
            case .success(let books):
                print("SEARCH \(fixture.name): \(books.count) books")
                if books.count < fixture.expectedMinimum {
                    let first = books.first?.name ?? "<none>"
                    failures.append(
                        "\(fixture.name): parsed \(books.count), expected >= \(fixture.expectedMinimum) (first=\(first))"
                    )
                }
            case .failure(let error):
                failures.append("\(fixture.name): \(error.displayMessage)")
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
