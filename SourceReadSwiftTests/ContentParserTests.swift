import XCTest
@testable import SourceReadSwift

final class ContentParserTests: XCTestCase {
    func testHTMLContentSplitsParagraphTags() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="content"><p>第一段</p><p>第二段<br>第三段</p></div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, ["第一段", "第二段", "第三段"])
    }

    func testHTMLContentAppliesReplaceRegex() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html",
                "replaceRegex": "广告.*?结束##"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="content"><p>正文第一段</p><p>广告这里删除结束正文第二段</p></div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, ["正文第一段", "正文第二段"])
    }

    func testHTMLContentAppliesGlobalPurifyRules() throws {
        let source = BookSource(
            bookSourceName: "Test",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="content"><p>正文第一段</p><p>请收藏本站广告尾巴</p></div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(
            source: source,
            chapter: chapter,
            response: response,
            globalPurifyRules: ["请收藏本站.*##"]
        )

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, ["正文第一段"])
    }

    func testContentAppliesJavaScriptReplaceRegex() throws {
        let source = BookSource(
            bookSourceName: "TestJS",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html",
                "replaceRegex": "<js>function x(a, b) { result = String(result).replace(a, b); } x(/#obf1#/g, '解密'); result;</js>"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="content"><p>这是#obf1#文本段落</p></div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, ["这是解密文本段落"])
    }

    func testContentParserSuppliesSrcAndBaseUrlToJavaScriptRules() throws {
        let source = BookSource(
            bookSourceName: "TestSrc",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": "<js>if (/flag1234/.test(src)) { result = 'FoundInSrc: ' + baseUrl; } else { result = 'No'; } result;</js>"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <!-- flag1234 -->
              <div class="content"><p>原文</p></div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, ["FoundInSrc: https://example.com/book/1/1.html"])
    }

    func testHTMLContentPreservesImagesAsTokens() throws {
        let source = BookSource(
            bookSourceName: "TestImg",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="content">
                <p>前文段落</p>
                <p><img src="https://img.example.com/cover1.jpg" alt="插图" /></p>
                <p>后文段落</p>
              </div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, [
            "前文段落",
            "[img]https://img.example.com/cover1.jpg[/img]",
            "后文段落"
        ])
    }

    func testImageDecodeRewritesImageURLWithJavaScript() throws {
        let source = BookSource(
            bookSourceName: "TestImageDecodeJS",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html",
                "imageDecode": "<js>result = result.replace('/thumb/', '/large/'); result;</js>"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="content">
                <p>前文段落</p>
                <p><img src="https://img.example.com/thumb/1.jpg" /></p>
              </div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, [
            "前文段落",
            "[img]https://img.example.com/large/1.jpg[/img]"
        ])
    }

    func testImageDecodeSupportsRegexReplacement() throws {
        let source = BookSource(
            bookSourceName: "TestImageDecodeRegex",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html",
                "imageDecode": "##/thumb/##/large/##"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="content"><p><img src="https://img.example.com/thumb/2.jpg" /></p></div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, ["[img]https://img.example.com/large/2.jpg[/img]"])
    }

    func testImageDecodeAbsolutizesRelativeResult() throws {
        let source = BookSource(
            bookSourceName: "TestImageDecodeRelative",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html",
                "imageDecode": "<js>result = '/images/cover.jpg';</js>"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="content"><p><img src="https://img.example.com/thumb/3.jpg" /></p></div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, ["[img]https://example.com/images/cover.jpg[/img]"])
    }

    func testImageDecodeKeepsOriginalURLWhenDecodeReturnsEmpty() throws {
        let source = BookSource(
            bookSourceName: "TestImageDecodeEmpty",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html",
                "imageDecode": "<js>result = '';</js>"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <div class="content"><p><img src="https://img.example.com/original.jpg" /></p></div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, ["[img]https://img.example.com/original.jpg[/img]"])
    }

    func testJSONContentAppliesImageDecode() throws {
        let source = BookSource(
            bookSourceName: "TestImageDecodeJSON",
            bookSourceUrl: "https://api.example.com",
            ruleContent: SourceRule(fields: [
                "content": "data.content",
                "imageDecode": "<js>result = result.replace('small', 'big'); result;</js>"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://api.example.com/c/1",
            bookUrl: "https://api.example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: #"{"data":{"content":"<p>前文</p><p><img src=\"https://img.example.com/small/2.jpg\"/></p>"}}"#,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, [
            "前文",
            "[img]https://img.example.com/big/2.jpg[/img]"
        ])
    }

    func testHTMLContentPropagatesImageStyle() throws {
        let source = BookSource(
            bookSourceName: "TestImageStyleHTML",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": "#content@textNodes",
                "imageStyle": "FULL"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://example.com/c/1",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: "<div id=\"content\"><p>第一段</p><p>第二段</p></div>",
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)
        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.imageStyle, "FULL")
        XCTAssertEqual(content.readerImageStyle, .full)
    }

    func testJSONContentPropagatesImageStyle() throws {
        let source = BookSource(
            bookSourceName: "TestImageStyleJSON",
            bookSourceUrl: "https://api.example.com",
            ruleContent: SourceRule(fields: [
                "content": "data.content",
                "imageStyle": "single"
            ])
        )
        let chapter = BookChapter(
            title: "Chapter 1",
            url: "https://api.example.com/c/1",
            bookUrl: "https://api.example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: #"{"data":{"content":"<p>正文内容</p>"}}"#,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)
        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.imageStyle, "single")
        XCTAssertEqual(content.readerImageStyle, .single)
    }

    func testHTMLContentTitleRuleOverridesTOCTitle() throws {
        let source = BookSource(
            bookSourceName: "Title fixture",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html",
                "title": "h1.chapter-title@text"
            ])
        )
        let chapter = BookChapter(
            title: "目录标题",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body>
              <h1 class="chapter-title">正文里的真实标题</h1>
              <div class="content"><p>第一段</p><p>第二段</p></div>
            </body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.title, "正文里的真实标题")
        XCTAssertEqual(content.chapter.title, "目录标题")
    }

    func testHTMLContentTitleRuleFallsBackWhenSelectorMisses() throws {
        let source = BookSource(
            bookSourceName: "Title fallback fixture",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html",
                "title": ".missing-title@text"
            ])
        )
        let chapter = BookChapter(
            title: "目录标题",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body><div class="content"><p>第一段</p></div></body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.title, "目录标题")
    }

    func testHTMLContentTitleRuleSupportsJavaScript() throws {
        let source = BookSource(
            bookSourceName: "Title JS fixture",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html",
                "title": "@js:'正文·' + chapter.title"
            ])
        )
        let chapter = BookChapter(
            title: "第一章",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: [:],
            body: """
            <html><body><div class="content"><p>第一段</p></div></body></html>
            """,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.title, "正文·第一章")
    }

    func testJSONContentTitleRuleOverridesTOCTitle() throws {
        let source = BookSource(
            bookSourceName: "JSON title fixture",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": "$.data.content",
                "title": "$.data.chapterTitle"
            ])
        )
        let chapter = BookChapter(
            title: "目录标题",
            url: "https://api.example.com/book/1",
            bookUrl: "https://api.example.com/book/1",
            index: 0,
            isVip: false
        )
        let response = SourceResponse(
            url: URL(string: chapter.url)!,
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: #"{"data":{"chapterTitle":"接口返回的标题","content":"<p>第一段</p><p>第二段</p>"}}"#,
            data: Data()
        )

        let result = ContentParser().parse(source: source, chapter: chapter, response: response)

        guard case .success(let content) = result else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.title, "接口返回的标题")
    }
}
