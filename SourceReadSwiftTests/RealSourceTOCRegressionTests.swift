import XCTest
@testable import SourceReadSwift

/// Chapter-list regression against pages captured from the same live sources
/// as `RealSourceSearchRegressionTests`.  Each `toc-*.body` file is the real
/// answer of the book page for the URL in `toc-index.json`, and
/// `expectedMinimum` is half of the row count the same `ruleToc` block yields
/// under Legado semantics (a floor, so a few navigation rows may differ).
/// Failure means a real source collapsed to Zero chapters -- the "目录为空"
/// report users keep sending.
final class RealSourceTOCRegressionTests: XCTestCase {
    private struct Fixture: Decodable {
        let name: String
        let bookSourceUrl: String
        let bookUrl: String
        let tocUrl: String
        let contentType: String
        let charset: String
        let bodyFile: String
        let emulated: Int
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
        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.appendingPathComponent("toc-index.json").path) {
            return candidate
        }
        throw XCTSkip("toc-index.json is missing from the test bundle")
    }

    func testCapturedTOCPagesReturnAtLeastTheirExpectedChapters() throws {
        let directory = try fixtureDirectory()
        let indexData = try Data(contentsOf: directory.appendingPathComponent("toc-index.json"))
        let fixtures = try JSONDecoder().decode([Fixture].self, from: indexData)
        XCTAssertFalse(fixtures.isEmpty, "toc fixture index decoded to zero entries")

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
            guard let tocURL = URL(string: fixture.tocUrl) else {
                failures.append("\(fixture.name): bad tocUrl")
                continue
            }
            let response = SourceResponse(
                url: tocURL,
                statusCode: 200,
                headers: headers,
                body: text,
                data: bodyData
            )
            let book = BookDetail(
                name: fixture.name,
                author: nil,
                coverUrl: nil,
                bookUrl: fixture.bookUrl,
                tocUrl: fixture.tocUrl,
                sourceName: fixture.name,
                sourceUrl: fixture.bookSourceUrl,
                intro: nil,
                latestChapter: nil
            )
            switch ChapterListParser().parse(source: fixture.source, book: book, response: response) {
            case .success(let chapters):
                print("TOC \(fixture.name): \(chapters.count) chapters (emulated \(fixture.emulated))")
                if chapters.count < fixture.expectedMinimum {
                    let first = chapters.first?.title ?? "<none>"
                    failures.append(
                        "\(fixture.name): parsed \(chapters.count), expected >= \(fixture.expectedMinimum) (emulated \(fixture.emulated), first=\(first))"
                    )
                }
            case .failure(let error):
                failures.append("\(fixture.name): \(error.displayMessage)")
            }
        }
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
