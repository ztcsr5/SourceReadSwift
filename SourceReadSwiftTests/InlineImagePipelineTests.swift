import UIKit
import XCTest
@testable import SourceReadSwift

final class InlineImagePipelineTests: XCTestCase {
    private static let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAMAAAACCAIAAAASFvFNAAAAGklEQVR42mNgYGhg0ADiACBmCACygTggoAEAMGgE4bJ9Q/wAAAAASUVORK5CYII="

    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        RemoteImageLoader.shared.clearCache()
        super.tearDown()
    }

    func testInlineImageDecoderRecognizesDataURIByteArrayAndRawBase64() throws {
        let expected = try XCTUnwrap(Data(base64Encoded: Self.pngBase64))

        guard case .decoded(let dataURIPayload) = InlineImageDecoder.decode("data:image/png;base64,\(Self.pngBase64)") else {
            return XCTFail("data URI should decode")
        }
        XCTAssertEqual(dataURIPayload.data, expected)
        XCTAssertEqual(dataURIPayload.fileExtension, "png")

        let byteArray = "[" + expected.map { String($0) }.joined(separator: ",") + "]"
        guard case .decoded(let bytePayload) = InlineImageDecoder.decode(byteArray) else {
            return XCTFail("JSON byte array should decode")
        }
        XCTAssertEqual(bytePayload.data, expected)

        let objectJSON = "{" + expected.enumerated().map { "\"\($0.offset)\":\($0.element)" }.joined(separator: ",") + "}"
        guard case .decoded(let objectPayload) = InlineImageDecoder.decode(objectJSON) else {
            return XCTFail("numeric-key byte object should decode")
        }
        XCTAssertEqual(objectPayload.data, expected)

        guard case .decoded(let rawPayload) = InlineImageDecoder.decode(Self.pngBase64) else {
            return XCTFail("raw base64 should decode")
        }
        XCTAssertEqual(rawPayload.data, expected)
    }

    func testInlineImageDecoderRejectsNonImageAndOrdinaryURLs() {
        let notImage = Data("not an image".utf8).base64EncodedString()
        guard case .invalid = InlineImageDecoder.decode("data:image/png;base64,\(notImage)") else {
            return XCTFail("non-image data URI must be rejected")
        }
        guard case .notInline = InlineImageDecoder.decode("https://img.example.com/cover.png") else {
            return XCTFail("ordinary URL must use the URL path")
        }
    }

    func testImageDecodeStoresInlineDataURIAndKeepsParagraphCompact() throws {
        let store = try makeStore()
        let parser = ContentParser(inlineImages: store)
        let source = makeSource(imageDecode: "<js>result = 'data:image/png;base64,\(Self.pngBase64)';</js>")
        let outcome = parser.parse(source: source, chapter: makeChapter(), response: makeResponse())

        guard case .success(let content) = outcome else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs.count, 2)
        XCTAssertEqual(content.paragraphs.first, "before")
        let paragraph = content.paragraphs[1]
        XCTAssertNotNil(paragraph.range(
            of: #"^\[img\]srdata://inline/[0-9a-f]{64}\.png\[/img\]$"#,
            options: .regularExpression
        ))
        XCTAssertLessThan(paragraph.count, 120)

        let url = try XCTUnwrap(ReaderImageSizingPolicy.imageURL(in: paragraph))
        XCTAssertTrue(InlineImageStore.isInlineURL(url))
        XCTAssertEqual(try XCTUnwrap(store.data(for: url)), expectedPNG)
    }

    func testImageDecodeReadsAjaxBytesAndLoadsThroughRemoteImageLoader() async throws {
        let store = try makeStore()
        let png = try XCTUnwrap(Data(base64Encoded: Self.pngBase64))
        let context = RuleExecutionContext()
        context.responseHandler = { _ in
            SourceResponse(
                url: URL(string: "https://img.example.com/raw.png")!,
                statusCode: 200,
                headers: ["Content-Type": "image/png"],
                body: "",
                data: png
            )
        }
        let parser = ContentParser(executionContext: context, inlineImages: store)
        let source = makeSource(imageDecode: "<js>result = java.ajaxBytes('https://img.example.com/raw.png');</js>")
        let outcome = parser.parse(source: source, chapter: makeChapter(), response: makeResponse())

        guard case .success(let content) = outcome else {
            return XCTFail("expected parsed content")
        }
        let url = try XCTUnwrap(content.paragraphs.compactMap { ReaderImageSizingPolicy.imageURL(in: $0) }.first)
        XCTAssertTrue(InlineImageStore.isInlineURL(url))
        XCTAssertEqual(try XCTUnwrap(store.data(for: url)), png)

        let loader = RemoteImageLoader(inlineImages: store)
        let loaded = await loader.image(for: url)
        let image = try XCTUnwrap(loaded)
        XCTAssertEqual(image.size.width, 3, accuracy: 0.01)
        XCTAssertEqual(image.size.height, 2, accuracy: 0.01)
        XCTAssertNotNil(loader.cachedImage(for: url))
    }

    func testImageDecodeRejectsMalformedInlinePayloadAndKeepsOriginalURL() throws {
        let store = try makeStore()
        let parser = ContentParser(inlineImages: store)
        let source = makeSource(imageDecode: "<js>result = 'data:image/png;base64,bm90LWFuLWltYWdl';</js>")
        let outcome = parser.parse(source: source, chapter: makeChapter(), response: makeResponse())

        guard case .success(let content) = outcome else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, [
            "before",
            "[img]https://img.example.com/original.png[/img]"
        ])
    }

    func testImageDecodeRejectsOutOfRangeByteArrayAndKeepsOriginalURL() throws {
        let store = try makeStore()
        let parser = ContentParser(inlineImages: store)
        let source = makeSource(imageDecode: "<js>result = [300, -1, 2];</js>")
        let outcome = parser.parse(source: source, chapter: makeChapter(), response: makeResponse())

        guard case .success(let content) = outcome else {
            return XCTFail("expected parsed content")
        }
        XCTAssertEqual(content.paragraphs, [
            "before",
            "[img]https://img.example.com/original.png[/img]"
        ])
    }

    func testInlineImageStoreDeduplicatesAndRejectsTraversal() throws {
        let store = try makeStore()
        let payload = InlineImagePayload(data: expectedPNG, fileExtension: "png")
        let first = try XCTUnwrap(store.store(payload))
        let second = try XCTUnwrap(store.store(payload))

        XCTAssertEqual(first, second)
        XCTAssertEqual(try XCTUnwrap(store.data(for: first)), expectedPNG)
        XCTAssertNil(store.data(for: URL(string: "srdata://inline/../chapter.json")!))
        XCTAssertNil(store.data(for: URL(string: "srdata://inline/\(String(repeating: "a", count: 64)).png")!))
    }

    private var expectedPNG: Data {
        Data(base64Encoded: Self.pngBase64)!
    }

    private func makeStore() throws -> InlineImageStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InlineImagePipelineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return InlineImageStore(directory: directory)
    }

    private func makeSource(imageDecode: String) -> BookSource {
        BookSource(
            bookSourceName: "InlineImagePipeline",
            bookSourceUrl: "https://example.com",
            ruleContent: SourceRule(fields: [
                "content": ".content@html",
                "imageDecode": imageDecode
            ])
        )
    }

    private func makeChapter() -> BookChapter {
        BookChapter(
            title: "Chapter 1",
            url: "https://example.com/book/1/1.html",
            bookUrl: "https://example.com/book/1",
            index: 0,
            isVip: false
        )
    }

    private func makeResponse() -> SourceResponse {
        let body = #"<html><body><div class="content"><p>before</p><p><img src="https://img.example.com/original.png" /></p></div></body></html>"#
        return SourceResponse(
            url: URL(string: "https://example.com/book/1/1.html")!,
            statusCode: 200,
            headers: [:],
            body: body,
            data: Data()
        )
    }
}
