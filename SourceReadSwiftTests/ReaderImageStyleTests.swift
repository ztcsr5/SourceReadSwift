import XCTest
import UIKit
@testable import SourceReadSwift

final class ReaderImageStyleTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        RemoteImageLoader.shared.clearCache()
    }

    func testReaderImageStyleParsing() {
        XCTAssertEqual(ReaderImageStyle(rule: "FULL"), .full)
        XCTAssertEqual(ReaderImageStyle(rule: "full"), .full)
        XCTAssertEqual(ReaderImageStyle(rule: "  FuLL  "), .full)
        XCTAssertEqual(ReaderImageStyle(rule: "DEFAULT"), .standard)
        XCTAssertEqual(ReaderImageStyle(rule: "default"), .standard)
        XCTAssertEqual(ReaderImageStyle(rule: nil), .standard)
        XCTAssertEqual(ReaderImageStyle(rule: ""), .standard)
        XCTAssertEqual(ReaderImageStyle(rule: "UNKNOWN_RULE"), .standard)
        XCTAssertEqual(ReaderImageStyle(rule: "TEXT"), .text)
        XCTAssertEqual(ReaderImageStyle(rule: "text"), .text)
        XCTAssertEqual(ReaderImageStyle(rule: "SINGLE"), .single)
        XCTAssertEqual(ReaderImageStyle(rule: "single"), .single)
    }

    func testReaderImageStyleProperties() {
        XCTAssertTrue(ReaderImageStyle.full.stretchesToColumnWidth)
        XCTAssertTrue(ReaderImageStyle.single.stretchesToColumnWidth)
        XCTAssertFalse(ReaderImageStyle.standard.stretchesToColumnWidth)
        XCTAssertFalse(ReaderImageStyle.text.stretchesToColumnWidth)

        XCTAssertTrue(ReaderImageStyle.single.reservesWholePage)
        XCTAssertFalse(ReaderImageStyle.full.reservesWholePage)
        XCTAssertFalse(ReaderImageStyle.standard.reservesWholePage)
    }

    func testImageURLParsing() {
        let validURL = "https://example.com/illustrations/cover.png"
        XCTAssertEqual(
            ReaderImageSizingPolicy.imageURL(in: "[img]\(validURL)[/img]")?.absoluteString,
            validURL
        )
        XCTAssertNil(ReaderImageSizingPolicy.imageURL(in: "这是一段普通的文字内容"))
        XCTAssertNil(ReaderImageSizingPolicy.imageURL(in: "[img][/img]"))
        XCTAssertNil(ReaderImageSizingPolicy.imageURL(in: "[img]   [/img]"))
        XCTAssertNil(ReaderImageSizingPolicy.imageURL(in: "[img]invalid url without scheme[/img]"))
        XCTAssertEqual(
            ReaderImageSizingPolicy.imageURL(in: "  [img]\(validURL)[/img]\n")?.absoluteString,
            validURL
        )
    }

    func testSizingPolicyFullStyleExpandsToColumnWidth() {
        let original = CGSize(width: 200, height: 100)
        let containerWidth: CGFloat = 360
        let calculated = ReaderImageSizingPolicy.size(
            for: original,
            style: .full,
            containerWidth: containerWidth
        )
        XCTAssertEqual(calculated.width, 360, accuracy: 0.01)
        XCTAssertEqual(calculated.height, 180, accuracy: 0.01)
    }

    func testSizingPolicyDefaultStylePreservesSmallerImage() {
        let original = CGSize(width: 200, height: 100)
        let containerWidth: CGFloat = 360
        let calculated = ReaderImageSizingPolicy.size(
            for: original,
            style: .standard,
            containerWidth: containerWidth
        )
        XCTAssertEqual(calculated.width, 200, accuracy: 0.01)
        XCTAssertEqual(calculated.height, 100, accuracy: 0.01)
    }

    func testSizingPolicyDefaultStyleShrinksOversizedImage() {
        let original = CGSize(width: 800, height: 400)
        let containerWidth: CGFloat = 360
        let calculated = ReaderImageSizingPolicy.size(
            for: original,
            style: .standard,
            containerWidth: containerWidth
        )
        XCTAssertEqual(calculated.width, 360, accuracy: 0.01)
        XCTAssertEqual(calculated.height, 180, accuracy: 0.01)
    }

    func testSizingPolicyEnforcesMaximumHeight() {
        let original = CGSize(width: 400, height: 800)
        let containerWidth: CGFloat = 400
        let calculated = ReaderImageSizingPolicy.size(
            for: original,
            style: .standard,
            containerWidth: containerWidth,
            maximumHeight: 260
        )
        XCTAssertEqual(calculated.height, 260, accuracy: 0.01)
        XCTAssertEqual(calculated.width, 130, accuracy: 0.01)
    }

    func testRemoteImageLoaderInsertAndLookup() {
        let url = URL(string: "https://example.com/cached.jpg")!
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
        let testImage = renderer.image { _ in }

        XCTAssertNil(RemoteImageLoader.shared.cachedImage(for: url))
        RemoteImageLoader.shared.insert(testImage, for: url)
        XCTAssertNotNil(RemoteImageLoader.shared.cachedImage(for: url))

        RemoteImageLoader.shared.clearCache()
        XCTAssertNil(RemoteImageLoader.shared.cachedImage(for: url))
    }

    func testNativeTextLayoutReplacesImageParagraphWithAttachment() {
        let imageURL = URL(string: "https://example.com/novel_illus.jpg")!
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 50))
        let testImage = renderer.image { _ in }
        RemoteImageLoader.shared.insert(testImage, for: imageURL)

        let config = NativeReaderTextView.Configuration(
            title: "插图测试",
            subtitle: nil,
            paragraphs: [
                "第一段文本描述",
                "[img]\(imageURL.absoluteString)[/img]",
                "第三段文本描述"
            ],
            contentFingerprint: "illus-test-1",
            fontSize: 18,
            lineSpacing: 8,
            pagePadding: 20,
            letterSpacing: 0,
            paragraphSpacing: 14,
            paragraphIndent: 0,
            titleSpacing: 10,
            footerHeight: 60,
            textColor: .label,
            highlightColor: .systemBlue,
            animatedScrollDuration: 0.35,
            imageStyle: .full,
            imageColumnWidth: 320
        )

        let result = ReaderNativeTextLayout.makeAttributedText(configuration: config)
        XCTAssertEqual(result.paragraphRanges.count, 3)
        // Image paragraph range is replaced by attachment character (length 1)
        XCTAssertEqual(result.paragraphRanges[1].length, 1)

        let attachmentRange = result.paragraphRanges[1]
        guard let attachment = result.text.attribute(.attachment, at: attachmentRange.location, effectiveRange: nil) as? NSTextAttachment else {
            return XCTFail("expected attachment")
        }
        XCTAssertEqual(attachment.bounds.width, 320, accuracy: 0.01)
        XCTAssertEqual(attachment.bounds.height, 160, accuracy: 0.01)
    }

    func testEstimatedPageCostFollowsImageStyle() {
        let budget = 1_000
        XCTAssertEqual(
            ReaderImageSizingPolicy.estimatedPageCost(for: .single, pageBudget: budget),
            budget
        )
        XCTAssertGreaterThan(
            ReaderImageSizingPolicy.estimatedPageCost(for: .full, pageBudget: budget),
            ReaderImageSizingPolicy.estimatedPageCost(for: .standard, pageBudget: budget)
        )
        XCTAssertEqual(
            ReaderImageSizingPolicy.estimatedPageCost(for: .standard, pageBudget: budget),
            ReaderImageSizingPolicy.estimatedPageCost(for: .text, pageBudget: budget)
        )
        XCTAssertEqual(ReaderImageSizingPolicy.estimatedPageCost(for: .standard, pageBudget: 0), 0)
    }

    func testMaximumIllustrationHeightFollowsStyle() {
        let single = ReaderImageSizingPolicy.maximumHeight(for: .single, viewportHeight: 800)
        let standard = ReaderImageSizingPolicy.maximumHeight(for: .standard, viewportHeight: 800)
        XCTAssertGreaterThan(single, standard)
        XCTAssertEqual(single, 624, accuracy: 0.01)
        XCTAssertEqual(standard, 496, accuracy: 0.01)
        XCTAssertEqual(
            ReaderImageSizingPolicy.maximumHeight(for: .standard, viewportHeight: 10),
            160,
            accuracy: 0.01
        )
    }

    func testNativeTextAttachmentUsesColumnDerivedMaximumHeight() {
        let imageURL = URL(string: "https://example.com/portrait_illustration.jpg")!
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 800))
        let testImage = renderer.image { _ in }
        RemoteImageLoader.shared.insert(testImage, for: imageURL)

        let config = NativeReaderTextView.Configuration(
            title: "插图高度测试",
            subtitle: nil,
            paragraphs: ["[img]\(imageURL.absoluteString)[/img]"],
            contentFingerprint: "illus-height-test",
            fontSize: 18,
            lineSpacing: 8,
            pagePadding: 20,
            letterSpacing: 0,
            paragraphSpacing: 14,
            paragraphIndent: 0,
            titleSpacing: 10,
            footerHeight: 60,
            textColor: .label,
            highlightColor: .systemBlue,
            animatedScrollDuration: 0.35,
            imageStyle: .standard,
            imageColumnWidth: 360
        )

        let result = ReaderNativeTextLayout.makeAttributedText(configuration: config)
        let attachmentRange = result.paragraphRanges[0]
        guard let attachment = result.text.attribute(.attachment, at: attachmentRange.location, effectiveRange: nil) as? NSTextAttachment else {
            return XCTFail("expected attachment")
        }
        XCTAssertEqual(attachment.bounds.height, 259.2, accuracy: 0.01)
        XCTAssertEqual(attachment.bounds.width, 129.6, accuracy: 0.01)
    }

    func testClearCacheIsIdempotentAndDropsImages() {
        let url = URL(string: "https://example.com/clear-cache.jpg")!
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20))
        RemoteImageLoader.shared.insert(renderer.image { _ in }, for: url)
        XCTAssertNotNil(RemoteImageLoader.shared.cachedImage(for: url))
        RemoteImageLoader.shared.clearCache()
        RemoteImageLoader.shared.clearCache()
        XCTAssertNil(RemoteImageLoader.shared.cachedImage(for: url))
    }

    func testSourceRequestBuilderProvidesImageHeaders() {
        let source = BookSource(
            bookSourceName: "ImageHeaderSource",
            bookSourceUrl: "https://book.cdn-images.org/index.html",
            header: #"{"User-Agent": "CustomReaderUA/1.0", "X-Asset-Key": "SecretVal"}"#
        )
        let builder = SourceRequestBuilder()
        let headers = builder.imageRequestHeaders(for: source)

        XCTAssertEqual(headers["User-Agent"], "CustomReaderUA/1.0")
        XCTAssertEqual(headers["X-Asset-Key"], "SecretVal")
        XCTAssertEqual(headers["Referer"], "https://book.cdn-images.org/")
        XCTAssertTrue(headers["Accept"]?.contains("image/") == true)
    }
}
