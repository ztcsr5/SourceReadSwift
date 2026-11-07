import XCTest
@testable import SourceReadSwift

/// Exercises the distributed definition itself; the network fixture never contacts its publisher.
final class UXXAggregatePipelineTests: XCTestCase {
    func testNovelDefinitionRunsSearchDetailDirectoryAndNestedContentRequest() async throws {
        let content = try await runPipeline(mode: "小说", category: "2", kind: .text)
        XCTAssertEqual(content.paragraphs, ["第一段原生回归正文。", "第二段保留完整内容。"])
        XCTAssertFalse(content.text.contains("script"))
    }

    func testComicDefinitionPreservesMediaKindAndLoadsNestedImageResponse() async throws {
        let content = try await runPipeline(mode: "漫画", category: "4", kind: .comic)
        XCTAssertEqual(ComicChapterResources(content: content).pages.map(\.url), [
            "https://uxxtv.com/images/page-1.webp", "https://uxxtv.com/images/page-2.webp"
        ])
    }

    private func runPipeline(mode: String, category: String, kind: BookSourceKind) async throws -> ChapterContent {
        let definition = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("docs/sources/uxx-aggregate-compatible.json")
        let source = try XCTUnwrap(JSONDecoder().decode([BookSource].self, from: Data(contentsOf: definition)).first)
        let network = UXXPipelineNetwork(category: category)
        let engine = LegadoSourceEngine(network: network)
        engine.allowWebViewFallback = false
        let menu = try await engine.exploreMenu(source: source).get()
        let action = try XCTUnwrap(menu.controls.first { $0.title.hasSuffix(" " + mode) }?.action)
        _ = try await engine.performExploreAction(source: source, action: action, inputs: [:]).get()

        let books = try await engine.searchBooks(source: source, keyword: "警花", page: 1).get()
        let book = try XCTUnwrap(books.first)
        XCTAssertEqual(books.count, 1)
        XCTAssertEqual(book.name, "警花演示")
        XCTAssertEqual(book.mediaKind, kind)
        XCTAssertEqual(book.bookUrl, "https://uxxtv.com/show/101.html?uxt=" + category)

        let detail = try await engine.getBookDetail(source: source, book: book).get()
        XCTAssertEqual(detail.mediaKind, kind)
        XCTAssertEqual(detail.intro, "完整简介，不应只剩标题。")
        let chapters = try await engine.getChapterList(source: source, book: detail).get()
        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        let chapter = try XCTUnwrap(chapters.first)
        XCTAssertEqual(chapter.bookUrl, book.bookUrl)
        let content = try await engine.getContent(source: source, chapter: chapter).get()
        let paths = network.requestedPaths
        XCTAssertEqual(paths.filter { $0 == "/" }.count, 1)
        XCTAssertTrue(paths.contains("/show/101.html"))
        XCTAssertTrue(paths.contains("/play/101/0/0.html"))
        XCTAssertEqual(paths.filter { $0 == network.contentPath }.count, 1)
        return content
    }
}

private final class UXXPipelineNetwork: SourceNetworkClient, @unchecked Sendable {
    let category: String
    private let lock = NSLock()
    private var recordedPaths: [String] = []

    init(category: String) { self.category = category }

    var contentPath: String { category == "4" ? "/uxxhmapi.php" : "/_getcontent.php" }
    var requestedPaths: [String] {
        lock.lock(); defer { lock.unlock() }
        return recordedPaths
    }

    func load(_ request: SourceRequest) async -> Result<SourceResponse, SourceEngineError> {
        let path = request.url.path.isEmpty ? "/" : request.url.path
        lock.lock(); recordedPaths.append(path); lock.unlock()
        let body: String
        switch path {
        case "/":
            guard URLComponents(url: request.url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "cid" })?.value == category else {
                return .failure(.rule("Aggregate search did not use the selected category"))
            }
            body = """
            <div class="list_1_box"><ul><li>
            <div class="cover_box"><a href="/play/101/0/0.html"><img class="cover" src="/cover.webp"></a></div>
            <div class="brief_box"><div class="title"><a>警花演示</a></div><div class="author">演示作者</div></div>
            </li></ul></div>
            """
        case "/show/101.html":
            body = """
            <div class="novel_box"><img class="cover" src="/cover.webp"></div>
            <div class="info_box"><h1>警花演示</h1><div class="update_state">连载</div></div>
            <div>作者：演示作者</div><div class="brief">小说简介：完整简介，不应只剩标题。</div>
            <ul class="catalog_ul"><li><a href="/play/101/0/0.html">第一章</a></li>
            <li><a href="/play/101/0/1.html">第二章</a></li></ul>
            """
        case "/play/101/0/0.html":
            body = "<html><iframe src=\"\(contentPath)?id=101\"></iframe></html>"
        case contentPath:
            body = category == "4"
                ? "<div><img data-src=\"/images/page-1.webp\"><img src=\"/images/page-2.webp\"></div>"
                : "<p>第一段原生回归正文。</p><script>ignored()</script><p>第二段保留完整内容。</p>"
        default:
            return .failure(.rule("Unexpected aggregate fixture path: \(path)"))
        }
        return .success(SourceResponse(url: request.url, statusCode: 200,
            headers: ["Content-Type": "text/html; charset=utf-8"], body: body, data: Data(body.utf8)))
    }
}
