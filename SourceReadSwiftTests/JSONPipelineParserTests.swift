import XCTest
@testable import SourceReadSwift

final class JSONPipelineParserTests: XCTestCase {
    func testParseHTMLSearchUsesInitContainer() throws {
        let source = BookSource(
            bookSourceName: "HTML源",
            bookSourceUrl: "https://html.example.com",
            ruleSearch: SourceRule(fields: [
                "init": "#results",
                "bookList": ".book",
                "name": ".title@text",
                "bookUrl": "a@href"
            ])
        )
        let response = SourceResponse(
            url: URL(string: "https://html.example.com/search")!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="book"><a class="title" href="/wrong">广告</a></div>
              <section id="results">
                <div class="book"><a class="title" href="/book/1">斗破苍穹</a></div>
              </section>
            </body></html>
            """,
            data: Data()
        )

        let result = SearchResultParser().parse(source: source, response: response)

        guard case .success(let books) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(books.map(\.name), ["斗破苍穹"])
        XCTAssertEqual(books.first?.bookUrl, "https://html.example.com/book/1")
    }

    func testParseJSONBookDetail() throws {
        let source = BookSource(
            bookSourceName: "API源",
            bookSourceUrl: "https://api.example.com",
            ruleBookInfo: SourceRule(fields: [
                "name": "data.name",
                "author": "data.author",
                "intro": "data.intro",
                "tocUrl": "data.toc"
            ])
        )
        let book = SearchBook(
            name: "旧名",
            author: nil,
            coverUrl: nil,
            bookUrl: "https://api.example.com/book/1",
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl,
            intro: nil
        )
        let response = SourceResponse(
            url: URL(string: book.bookUrl)!,
            statusCode: 200,
            headers: [:],
            body: #"{"data":{"name":"斗破苍穹","author":"天蚕土豆","intro":"简介","toc":"/book/1/catalog"}}"#,
            data: Data()
        )

        let result = BookDetailParser().parse(source: source, book: book, response: response)
        guard case .success(let detail) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(detail.name, "斗破苍穹")
        XCTAssertEqual(detail.author, "天蚕土豆")
        XCTAssertEqual(detail.tocUrl, "https://api.example.com/book/1/catalog")
    }

    func testParseJSONBookDetailKeepsSearchFieldsWhenDetailIsBlank() throws {
        let source = BookSource(
            bookSourceName: "API",
            bookSourceUrl: "https://api.example.com",
            ruleBookInfo: SourceRule(fields: [
                "name": "data.name",
                "author": "data.author",
                "coverUrl": "data.cover",
                "intro": "data.intro",
                "tocUrl": "data.toc"
            ])
        )
        let book = SearchBook(
            name: "Search Name",
            author: "Search Author",
            coverUrl: "https://img.example.com/search.jpg",
            bookUrl: "https://api.example.com/book/1",
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl,
            intro: "Search intro"
        )
        let response = SourceResponse(
            url: URL(string: book.bookUrl)!,
            statusCode: 200,
            headers: [:],
            body: #"{"data":{"name":"","author":"","cover":"","intro":"","toc":""}}"#,
            data: Data()
        )

        let result = BookDetailParser().parse(source: source, book: book, response: response)

        guard case .success(let detail) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(detail.name, book.name)
        XCTAssertEqual(detail.author, book.author)
        XCTAssertEqual(detail.coverUrl, book.coverUrl)
        XCTAssertEqual(detail.intro, book.intro)
        XCTAssertNil(detail.tocUrl)
    }

    func testParseJSONChapterList() throws {
        let source = BookSource(
            bookSourceName: "API源",
            bookSourceUrl: "https://api.example.com",
            ruleToc: SourceRule(fields: [
                "chapterList": "data.chapters",
                "chapterName": "title",
                "chapterUrl": "url"
            ])
        )
        let book = BookDetail(
            name: "斗破苍穹",
            author: nil,
            coverUrl: nil,
            bookUrl: "https://api.example.com/book/1",
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl,
            intro: nil,
            latestChapter: nil
        )
        let response = SourceResponse(
            url: URL(string: book.bookUrl)!,
            statusCode: 200,
            headers: [:],
            body: #"{"data":{"chapters":[{"title":"第一章","url":"/c/1"}]}}"#,
            data: Data()
        )

        let result = ChapterListParser().parse(source: source, book: book, response: response)
        guard case .success(let chapters) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(chapters.first?.title, "第一章")
        XCTAssertEqual(chapters.first?.url, "https://api.example.com/c/1")
    }

    func testParseJSONContentUsesInitContainer() throws {
        let source = BookSource(
            bookSourceName: "API源",
            bookSourceUrl: "https://api.example.com",
            ruleContent: SourceRule(fields: [
                "init": "data.payload",
                "content": "body"
            ])
        )
        let chapter = BookChapter(
            title: "第一章",
            url: "https://api.example.com/c/1",
            bookUrl: "https://api.example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: #"{"data":{"payload":{"body":"第一段\n第二段"}}}"#,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)
        guard case .success(let content) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(content.paragraphs, ["第一段", "第二段"])
    }

    func testParseJSONContent() throws {
        let source = BookSource(
            bookSourceName: "API源",
            bookSourceUrl: "https://api.example.com",
            ruleContent: SourceRule(fields: [
                "content": "data.content"
            ])
        )
        let chapter = BookChapter(
            title: "第一章",
            url: "https://api.example.com/c/1",
            bookUrl: "https://api.example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: #"{"data":{"content":"第一段\n第二段"}}"#,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)
        guard case .success(let content) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(content.paragraphs, ["第一段", "第二段"])
    }

    func testParseJSONBookDetailInitReceivesBookAndBaseURLContext() throws {
        let source = BookSource(
            bookSourceName: "JS Init",
            bookSourceUrl: "https://api.example.com",
            ruleBookInfo: SourceRule(fields: [
                "init": #"@js:JSON.stringify({data:{name:book.name, toc:baseUrl + "/toc"}})"#,
                "name": "$.data.name",
                "tocUrl": "$.data.toc"
            ])
        )
        let book = SearchBook(
            name: "上下文书名",
            author: nil,
            coverUrl: nil,
            bookUrl: "https://api.example.com/book/1",
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl
        )
        let response = SourceResponse(
            url: URL(string: book.bookUrl)!,
            statusCode: 200,
            headers: [:],
            body: #"{"data":{"name":"原始名"}}"#,
            data: Data()
        )

        let result = BookDetailParser().parse(source: source, book: book, response: response)
        guard case .success(let detail) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(detail.name, "上下文书名")
        XCTAssertEqual(detail.tocUrl, "https://api.example.com/book/1/toc")
    }

    func testParseJSONSearchDecodesStringifiedInitContainer() throws {
        let source = BookSource(
            bookSourceName: "Search Init",
            bookSourceUrl: "https://api.example.com",
            ruleSearch: SourceRule(fields: [
                "init": #"@js:JSON.stringify({data:{list:[{title:'初始化书',url:'/book/init-1'}]}})"#,
                "bookList": "$.data.list",
                "name": "$.title",
                "bookUrl": "$.url"
            ])
        )
        let response = SourceResponse(
            url: URL(string: "https://api.example.com/search?q=x")!,
            statusCode: 200,
            headers: [:],
            body: #"{"ignored":true}"#,
            data: Data()
        )

        let result = SearchResultParser().parse(source: source, response: response)
        guard case .success(let books) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(books.map(\.name), ["初始化书"])
        XCTAssertEqual(books.first?.bookUrl, "https://api.example.com/book/init-1")
    }

    func testParseJSONChapterListDecodesStringifiedInitContainer() throws {
        let source = BookSource(
            bookSourceName: "TOC Init",
            bookSourceUrl: "https://api.example.com",
            ruleToc: SourceRule(fields: [
                "init": #"@js:JSON.stringify({data:{chapters:[{title:'初始化章',url:'/c/init-1'}]}})"#,
                "chapterList": "$.data.chapters",
                "chapterName": "$.title",
                "chapterUrl": "$.url"
            ])
        )
        let book = BookDetail(
            name: "书", author: nil, coverUrl: nil,
            bookUrl: "https://api.example.com/book/1",
            tocUrl: "https://api.example.com/book/1/toc",
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl,
            intro: nil, latestChapter: nil
        )
        let response = SourceResponse(
            url: URL(string: "https://api.example.com/book/1/toc")!,
            statusCode: 200,
            headers: [:],
            body: #"{"ignored":true}"#,
            data: Data()
        )

        let result = ChapterListParser().parse(source: source, book: book, response: response)
        guard case .success(let page) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(page.chapters.map(\.title), ["初始化章"])
        XCTAssertEqual(page.chapters.first?.url, "https://api.example.com/c/init-1")
    }

    func testParseJSONContentDecodesStringifiedInitContainer() throws {
        let source = BookSource(
            bookSourceName: "Content Init",
            bookSourceUrl: "https://api.example.com",
            ruleContent: SourceRule(fields: [
                "init": #"@js:JSON.stringify({data:{payload:{body:'初始化正文\n第二段'}}})"#,
                "content": "$.data.payload.body"
            ])
        )
        let chapter = BookChapter(
            title: "第一章",
            url: "https://api.example.com/c/init-1",
            bookUrl: "https://api.example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: #"{"ignored":true}"#,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)
        guard case .success(let content) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(content.paragraphs, ["初始化正文", "第二段"])
    }

    func testParseJSONSearchRunsJSInitAgainstNonJSONBody() throws {
        let source = BookSource(
            bookSourceName: "Search Raw Init",
            bookSourceUrl: "https://api.example.com",
            ruleSearch: SourceRule(fields: [
                "init": #"@js:JSON.stringify({data:{list:[{title:result.split('|')[0],url:result.split('|')[1]}]}})"#,
                "bookList": "$.data.list",
                "name": "$.title",
                "bookUrl": "$.url"
            ])
        )
        let response = SourceResponse(
            url: URL(string: "https://api.example.com/search?q=x")!,
            statusCode: 200,
            headers: [:],
            body: "非JSON书|/book/raw-1",
            data: Data()
        )

        let result = SearchResultParser().parse(source: source, response: response)
        guard case .success(let books) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(books.map(\.name), ["非JSON书"])
        XCTAssertEqual(books.first?.bookUrl, "https://api.example.com/book/raw-1")
    }

    func testParseJSONChapterListRunsJSInitAgainstNonJSONBody() throws {
        let source = BookSource(
            bookSourceName: "TOC Raw Init",
            bookSourceUrl: "https://api.example.com",
            ruleToc: SourceRule(fields: [
                "init": #"@js:JSON.stringify({data:{chapters:[{title:result.split('|')[0],url:result.split('|')[1]}]}})"#,
                "chapterList": "$.data.chapters",
                "chapterName": "$.title",
                "chapterUrl": "$.url"
            ])
        )
        let book = BookDetail(
            name: "书", author: nil, coverUrl: nil,
            bookUrl: "https://api.example.com/book/1",
            tocUrl: "https://api.example.com/book/1/toc",
            sourceName: source.bookSourceName,
            sourceUrl: source.bookSourceUrl,
            intro: nil, latestChapter: nil
        )
        let response = SourceResponse(
            url: URL(string: "https://api.example.com/book/1/toc")!,
            statusCode: 200,
            headers: [:],
            body: "原始章|/c/raw-1",
            data: Data()
        )

        let result = ChapterListParser().parse(source: source, book: book, response: response)
        guard case .success(let page) = result else {
            return XCTFail("expected success, got \(result)")
        }
        XCTAssertEqual(page.chapters.map(\.title), ["原始章"])
        XCTAssertEqual(page.chapters.first?.url, "https://api.example.com/c/raw-1")
    }
}
